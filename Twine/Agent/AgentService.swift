import Foundation
import MotionAgent

/// Where Twine listens for AI apps: a Unix socket in its own Application
/// Support folder, which only this Mac user can reach. The test copy has
/// its own bundle id, so its own socket, and never answers for the
/// person's Twine.
nonisolated enum AgentSocket {
    static var url: URL {
        let id = Bundle.main.bundleIdentifier ?? "com.nidhin.twine"
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent(id, isDirectory: true).appendingPathComponent("agent.sock")
        // A socket's path has room for 103 bytes; a long home folder goes
        // to the user's own temporary folder instead, which is as private.
        if url.path.utf8.count < 100 { return url }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(id).agent.sock")
    }

    /// An address for the socket at `path`, or nil when it does not fit.
    static func address(_ path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    /// A connected socket, or -1 when nothing listens there.
    static func connect(_ path: String) -> Int32 {
        guard var address = address(path) else { return -1 }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return -1 }
        let ok = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        guard ok else { close(fd); return -1 }
        noSignalOnWrite(fd)
        return fd
    }

    /// Writing to a socket whose other end has gone fails rather than
    /// stopping the app.
    static func noSignalOnWrite(_ fd: Int32) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    /// Writes all of `data`, false when the other end has gone.
    @discardableResult
    static func write(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { raw in
            guard var p = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                let n = Darwin.write(fd, p, left)
                if n < 0 { if errno == EINTR { continue }; return false }
                p += n
                left -= n
            }
            return true
        }
    }
}

/// Listens on `AgentSocket` while Settings allows AI apps, answering each
/// connection's messages with `TwineAgent`'s tools on the main thread. The
/// bridge (`Twine --mcp`, which AI apps start) is what connects.
@MainActor
final class AgentService {
    static let shared = AgentService()

    private var listener: Listener?
    private lazy var server = TwineAgent(host: AppAgentHost()).server(version: "\(VersionHistory.version)")

    /// Starts or stops as Settings says.
    func update() {
        if AppSettings.shared.allowsAgents {
            guard listener == nil else { return }
            let server = self.server
            listener = Listener(path: AgentSocket.url.path) { line in
                await server.handle(line)
            }
            if listener?.start() != true { listener = nil }
        } else {
            listener?.stop()
            listener = nil
        }
    }

    func stop() {
        listener?.stop()
        listener = nil
    }

    var isListening: Bool { listener != nil }
}

/// The socket itself: accepting, reading lines and writing replies, on a
/// queue of its own; only the answering happens on the main thread.
private nonisolated final class Listener: @unchecked Sendable {
    typealias Answer = @MainActor (Data) async -> Data?

    private let path: String
    private let answer: Answer
    private let queue = DispatchQueue(label: "com.nidhin.twine.agent")
    private var fd: Int32 = -1
    private var accepting: DispatchSourceRead?
    private var connections: [Int32: Connection] = [:]

    init(path: String, answer: @escaping Answer) {
        self.path = path
        self.answer = answer
    }

    func start() -> Bool {
        let folder = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        // Another Twine of the same id answering already keeps it; a socket
        // left by one that stopped is cleared.
        let other = AgentSocket.connect(path)
        if other >= 0 { close(other); return false }
        unlink(path)
        guard var address = AgentSocket.address(path) else { return false }
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) == 0
            }
        }
        // Only this user can connect.
        guard bound, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            close(fd)
            fd = -1
            return false
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        accepting = source
        return true
    }

    func stop() {
        queue.sync {
            accepting?.cancel()
            accepting = nil
            for connection in connections.values { connection.close() }
            connections = [:]
            if fd >= 0 { close(fd); fd = -1 }
            unlink(path)
        }
    }

    private func accept() {
        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { return }
        AgentSocket.noSignalOnWrite(client)
        let connection = Connection(fd: client, queue: queue, answer: answer) { [weak self] in
            self?.connections[client] = nil
        }
        connections[client] = connection
        connection.start()
    }
}

/// One AI app's connection: lines in, a reply out for each request.
private nonisolated final class Connection: @unchecked Sendable {
    private let fd: Int32
    private let queue: DispatchQueue
    private let answer: Listener.Answer
    private let ended: () -> Void
    private var reading: DispatchSourceRead?
    private var buffer = Data()
    private var isOpen = true

    init(fd: Int32, queue: DispatchQueue, answer: @escaping Listener.Answer, ended: @escaping () -> Void) {
        self.fd = fd
        self.queue = queue
        self.answer = answer
        self.ended = ended
    }

    func start() {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.read() }
        source.resume()
        reading = source
    }

    /// Called on the queue.
    func close() {
        guard isOpen else { return }
        isOpen = false
        reading?.cancel()
        reading = nil
        Darwin.close(fd)
    }

    private func read() {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let n = Darwin.read(fd, &chunk, chunk.count)
        guard n > 0 else {
            close()
            ended()
            return
        }
        buffer.append(contentsOf: chunk[0..<n])
        // A message past 64 MB is not one an AI app sends.
        if buffer.count > 64 << 20 { buffer.removeAll(); return }
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            guard !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D }) else { continue }
            let answer = self.answer
            Task { @MainActor [weak self] in
                guard let reply = await answer(line) else { return }
                self?.send(reply)
            }
        }
    }

    private func send(_ reply: Data) {
        queue.async { [self] in
            guard isOpen else { return }
            if !AgentSocket.write(reply, to: fd) { close(); ended() }
        }
    }
}
