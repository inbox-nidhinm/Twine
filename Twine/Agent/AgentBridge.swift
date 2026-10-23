import AppKit
import MotionAgent

/// `Twine --mcp`: what an AI app starts to reach Twine. It is Twine's own
/// program run without its windows, passing the app's messages (lines of
/// JSON on standard input) to the running Twine's socket and the replies
/// back out. It answers the handshake, the tool list and pings itself
/// (`MCPServer.answer`), since every Claude session starts a bridge and
/// says hello at once, whether or not it ever uses Twine: answered by
/// Twine, that opened Twine with every new session and reopened it after
/// every quit. A tool call opens Twine, in the background, when it is not
/// running, and again if it quits between calls. A request Twine never
/// answered because it quit gets an error reply, so the AI app is not
/// left waiting.
nonisolated enum AgentBridge {
    static let argument = "--mcp"

    /// The program to start, as AI apps are told it.
    static var executable: String { Bundle.main.executablePath ?? "/Applications/Twine.app/Contents/MacOS/Twine" }

    /// The line that adds Twine to Claude Code.
    static var claudeCommand: String {
        "claude mcp add --scope user twine -- '\(executable.replacingOccurrences(of: "'", with: "'\\''"))' \(argument)"
    }

    static func run() -> Never {
        signal(SIGPIPE, SIG_IGN)
        let link = Link()
        let listing = MainActor.assumeIsolated { TwineAgent.listing(version: VersionHistory.version) }
        while let line = readLine(strippingNewline: true) {
            guard !line.allSatisfy(\.isWhitespace) else { continue }
            switch listing.answer(Data(line.utf8)) {
            case .silent: continue
            case .answered(let reply): link.write(reply)
            case .toolCall: link.send(line)
            }
        }
        exit(0)
    }

    /// The connection to Twine, made again whenever it has gone.
    private final class Link: @unchecked Sendable {
        private let lock = NSLock()
        private var fd: Int32 = -1
        /// Requests sent and not yet answered, by their id's JSON.
        private var waiting: [String: Any] = [:]
        private let output = FileHandle.standardOutput

        func send(_ line: String) {
            let id = Self.requestID(line)
            lock.lock()
            if fd < 0 { fd = connected() }
            let socket = fd
            if let id, socket >= 0 { waiting[id.key] = id.value }
            lock.unlock()
            guard socket >= 0 else {
                if let id { reply(error: Self.refusal, to: id.value) }
                return
            }
            if !AgentSocket.write(Data((line + "\n").utf8), to: socket) {
                dropped(socket)
                if let id { reply(error: Self.refusal, to: id.value) }
            }
        }

        private static var refusal: String {
            "Twine is not answering. Open Twine, and check Settings > AI apps > Let AI apps use Twine is on."
        }

        /// Connects, opening Twine first if nothing answers, waiting up to
        /// 30 seconds for it to start, or a few when it was open already
        /// (AI apps are then switched off in its Settings).
        private func connected() -> Int32 {
            let path = AgentSocket.url.path
            var fd = AgentSocket.connect(path)
            if fd >= 0 { return listen(fd) }
            let wasOpen = Bundle.main.bundleIdentifier.map {
                !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty
            } ?? false
            let open = Process()
            open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            open.arguments = ["-g", Bundle.main.bundlePath]
            try? open.run()
            open.waitUntilExit()
            let deadline = Date().addingTimeInterval(wasOpen ? 4 : 30)
            while Date() < deadline {
                usleep(200_000)
                fd = AgentSocket.connect(path)
                if fd >= 0 { return listen(fd) }
            }
            return -1
        }

        /// Copies Twine's replies out, line by line, on a thread of its own.
        private func listen(_ fd: Int32) -> Int32 {
            Thread.detachNewThread { [self] in
                var buffer = Data()
                var chunk = [UInt8](repeating: 0, count: 65_536)
                while true {
                    let n = read(fd, &chunk, chunk.count)
                    if n < 0, errno == EINTR { continue }
                    guard n > 0 else { break }
                    buffer.append(contentsOf: chunk[0..<n])
                    while let newline = buffer.firstIndex(of: 0x0A) {
                        let line = Data(buffer[buffer.startIndex...newline])
                        buffer.removeSubrange(buffer.startIndex...newline)
                        if let id = Self.replyID(line) {
                            lock.lock()
                            waiting[id] = nil
                            lock.unlock()
                        }
                        write(line)
                    }
                }
                dropped(fd)
            }
            return fd
        }

        /// Twine went: what it was asked and did not answer gets an error.
        private func dropped(_ socket: Int32) {
            lock.lock()
            guard fd == socket else { lock.unlock(); return }
            close(socket)
            fd = -1
            let unanswered = waiting
            waiting = [:]
            lock.unlock()
            for id in unanswered.values { reply(error: "Twine closed before answering. Ask again: it will be opened.", to: id) }
        }

        private func reply(error message: String, to id: Any) {
            let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": -32000, "message": message]]
            guard var data = try? JSONSerialization.data(withJSONObject: body) else { return }
            data.append(0x0A)
            write(data)
        }

        private let writing = NSLock()

        func write(_ data: Data) {
            writing.lock()
            output.write(data)
            writing.unlock()
        }

        /// A request's id, as text to key it by and as it was.
        private static func requestID(_ line: String) -> (key: String, value: Any)? {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["method"] != nil, let id = object["id"], !(id is NSNull) else { return nil }
            return (key(id), id)
        }

        private static func replyID(_ line: Data) -> String? {
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["method"] == nil, let id = object["id"] else { return nil }
            return key(id)
        }

        private static func key(_ id: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: id, options: .fragmentsAllowed))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "\(id)"
        }
    }
}
