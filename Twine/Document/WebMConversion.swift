import Foundation

/// WebM files, which macOS cannot open, made into movies it can, with the
/// ffmpeg already installed on this Mac (the user's choice, 28 September
/// 2026). A clip with transparency becomes ProRes 4444, which keeps it;
/// others become high-quality HEVC, or ProRes 422 where the Mac has no HEVC
/// encoder. Every sound track comes along. The movie is written to a
/// temporary folder and imported from there like any other.
enum WebMConversion {
    enum Failure: LocalizedError {
        case noFFmpeg
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .noFFmpeg: "WebM needs ffmpeg, which isn't installed on this Mac."
            case .failed(let reason): reason
            }
        }
    }

    static func isWebM(_ url: URL) -> Bool { url.pathExtension.lowercased() == "webm" }

    /// Where Homebrew and other installers put ffmpeg. An app started from
    /// the Finder does not see the shell's search path, so it looks itself.
    private static let places = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/bin"]

    static func tool(_ name: String) -> URL? {
        places.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    /// A movie made from `url`, in a temporary folder.
    static func convert(_ url: URL) async throws -> URL {
        guard let ffmpeg = tool("ffmpeg") else { throw Failure.noFFmpeg }
        let video = await probe(url)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Twine WebM", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(UUID().uuidString + ".mov")
        var input: [String] = ["-hide_banner", "-loglevel", "error", "-y"]
        // ffmpeg's own VP8 and VP9 decoders drop the alpha channel; libvpx keeps it.
        if video.hasAlpha { input += ["-c:v", video.codec == "vp8" ? "libvpx" : "libvpx-vp9"] }
        input += ["-i", url.path, "-map", "0:v:0", "-map", "0:a?", "-fps_mode", "passthrough"]
        let attempts: [[String]] = video.hasAlpha
            ? [["-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le", "-c:a", "pcm_s16le"]]
            : [["-c:v", "hevc_videotoolbox", "-q:v", "70", "-tag:v", "hvc1", "-pix_fmt", "yuv420p",
                "-c:a", "aac", "-b:a", "320k"],
               ["-c:v", "prores_ks", "-profile:v", "2", "-pix_fmt", "yuv422p10le", "-c:a", "pcm_s16le"]]
        var reason = ""
        for settings in attempts {
            let (status, errors) = try await run(ffmpeg, input + settings + [out.path])
            if status == 0, FileManager.default.fileExists(atPath: out.path) { return out }
            reason = errors
            try? FileManager.default.removeItem(at: out)
        }
        let detail = reason.split(separator: "\n").last.map(String.init) ?? "ffmpeg stopped."
        throw Failure.failed("\(url.lastPathComponent) couldn't be converted: \(detail)")
    }

    /// The first video stream's codec, and whether it carries transparency.
    private static func probe(_ url: URL) async -> (codec: String, hasAlpha: Bool) {
        guard let ffprobe = tool("ffprobe"),
              let (_, output) = try? await run(ffprobe, ["-v", "error", "-select_streams", "v:0",
                                                        "-show_entries", "stream=codec_name:stream_tags=alpha_mode",
                                                        "-of", "default=noprint_wrappers=1", url.path], readsOutput: true)
        else { return ("vp9", false) }
        let codec = output.split(separator: "\n").first { $0.hasPrefix("codec_name=") }.map { String($0.dropFirst(11)) } ?? "vp9"
        return (codec, output.contains("alpha_mode=1"))
    }

    /// Runs a tool to the end without holding up the main thread, and
    /// returns its exit status with what it printed (its errors, or with
    /// `readsOutput`, its output).
    private static func run(_ tool: URL, _ arguments: [String], readsOutput: Bool = false) async throws -> (Int32, String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = tool
            process.arguments = arguments
            let pipe = Pipe()
            if readsOutput { process.standardOutput = pipe } else { process.standardError = pipe }
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: (finished.terminationStatus, text))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
