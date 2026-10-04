import AppKit
import AVFoundation
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import MotionModel

/// Reading a file that is being imported: what kind it is, its size and
/// length, and a fingerprint of its bytes, so the same file imported twice
/// is stored once.
enum MediaImport {
    /// What the open panel offers and a drop accepts.
    static let types: [UTType] = [.image, .movie, .audio]

    static func kind(of url: URL) -> MediaKind? {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else { return nil }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return nil
    }

    /// Everything about the file the project keeps, under a new id. Nil for a
    /// file that is not a picture, a video or a sound, or will not open.
    static func describe(_ url: URL) async -> MediaAsset? {
        guard let kind = kind(of: url), let hash = await fingerprint(url) else { return nil }
        let id = UUID()
        let ext = url.pathExtension.lowercased()
        var asset = MediaAsset(id: id, kind: kind, fileName: ext.isEmpty ? id.uuidString : "\(id.uuidString).\(ext)",
                               originalName: url.lastPathComponent, contentHash: hash)
        switch kind {
        case .image:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  var w = properties[kCGImagePropertyPixelWidth] as? Int,
                  var h = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
            // Orientations 5 to 8 are turned a quarter, so width and height swap.
            if let o = properties[kCGImagePropertyOrientation] as? Int, o >= 5 { swap(&w, &h) }
            guard FileSafety.pictureFileFits(width: Double(w), height: Double(h)) else { return nil }
            asset.pixelWidth = w
            asset.pixelHeight = h
        case .video:
            let file = AVURLAsset(url: url)
            guard let track = try? await file.loadTracks(withMediaType: .video).first,
                  let natural = try? await track.load(.naturalSize),
                  let transform = try? await track.load(.preferredTransform),
                  let duration = try? await file.load(.duration) else { return nil }
            let turned = natural.applying(transform)
            asset.pixelWidth = Int(abs(turned.width).rounded())
            asset.pixelHeight = Int(abs(turned.height).rounded())
            asset.duration = duration.seconds
            asset.hasAudio = !((try? await file.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        case .audio:
            let file = AVURLAsset(url: url)
            guard let duration = try? await file.load(.duration), duration.seconds > 0 else { return nil }
            asset.duration = duration.seconds
            asset.hasAudio = true
        }
        return asset
    }

    /// Whether `url` is a picture too large to take in
    /// (`FileSafety.pictureFileFits`), read from its header alone.
    static func isOversizedPicture(_ url: URL) -> Bool {
        guard kind(of: url) == .image, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = properties[kCGImagePropertyPixelWidth] as? Int,
              let h = properties[kCGImagePropertyPixelHeight] as? Int else { return false }
        return !FileSafety.pictureFileFits(width: Double(w), height: Double(h))
    }

    /// What a notice says of pictures too large to take in.
    static func oversizedNotice(_ names: [String]) -> String {
        names.count == 1 ? "\(names[0]) is too large to import." : "\(names.joined(separator: ", ")) are too large to import."
    }

    // MARK: The clipboard

    /// Files copied in the Finder that can be imported (pictures, video,
    /// sound and SVG drawings). Nil when the clipboard holds no files; empty
    /// when it holds only files of other kinds, whose icon the Finder also
    /// puts there as a picture, which is not what was copied.
    static func copiedFiles(on board: NSPasteboard) -> [URL]? {
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else { return nil }
        return urls.filter { kind(of: $0) != nil || $0.pathExtension.lowercased() == "svg" }
    }

    /// A picture's own types, best first, each with the extension it is kept under.
    private static let pictureTypes: [(type: NSPasteboard.PasteboardType, ext: String)] = [
        (.png, "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (NSPasteboard.PasteboardType(UTType.heic.identifier), "heic"),
        (.tiff, "tiff"),
    ]

    /// A copied picture (a screenshot, a picture copied in a browser or as
    /// PNG from Figma) as file bytes and the extension to keep them under.
    /// TIFF, which the system copies uncompressed, is kept as PNG.
    enum CopiedPicture {
        case picture(Data, ext: String)
        /// Past `FileSafety.pictureFileFits`, judged from its header.
        case tooLarge
    }

    static func copiedPicture(on board: NSPasteboard) -> CopiedPicture? {
        for (type, ext) in pictureTypes {
            guard let data = board.data(forType: type),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
            // A TIFF from the system can hold the picture at several sizes: take the largest.
            let sizes = (0..<CGImageSourceGetCount(source)).compactMap { i -> (index: Int, w: Int, h: Int)? in
                guard let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                      let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int
                else { return nil }
                return (i, w, h)
            }
            guard let largest = sizes.max(by: { $0.w * $0.h < $1.w * $1.h }) else { continue }
            guard FileSafety.pictureFileFits(width: Double(largest.w), height: Double(largest.h)) else { return .tooLarge }
            if type != .tiff { return .picture(data, ext: ext) }
            guard let png = pngData(from: source, at: largest.index) else { continue }
            return .picture(png, ext: "png")
        }
        return nil
    }

    /// One picture of `source` written as PNG, its colour space kept.
    private static func pngData(from source: CGImageSource, at index: Int) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImageFromSource(destination, source, index, nil)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }

    /// SHA-256 of the file, read a megabyte at a time so a long video never
    /// has to fit in memory.
    static func fingerprint(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                hasher.update(data: chunk)
            }
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }.value
    }
}
