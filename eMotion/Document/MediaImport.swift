import Foundation
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
