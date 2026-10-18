import Foundation

/// The pictures a template shows in its empty slots, so a new template
/// looks like something before any of the user's own go in (the user's
/// choice of pictures, 19 October 2026). They ship with the app
/// (`template-sample-NN.jpg` in its resources), are never part of a
/// project's media, and are known by these fixed ids, which the app's
/// media library finds in its own bundle.
public enum TemplateSamples {
    public struct Sample: Sendable, Equatable {
        public let id: UUID
        /// The file in the app's resources.
        public let fileName: String
        /// Its size in pixels.
        public let size: Size2
    }

    public static let all: [Sample] = [
        (540, 720), (735, 914), (1024, 576), (771, 1024), (1024, 1024),
        (1024, 1024), (819, 1024), (1024, 1024), (512, 1024), (1024, 1024),
    ].enumerated().map { i, size in
        Sample(id: UUID(uuidString: String(format: "7E3A5A3D-5A3D-4E3A-8000-0000000000%02d", i + 1))!,
               fileName: String(format: "template-sample-%02d.jpg", i + 1), size: Size2(Double(size.0), Double(size.1)))
    }

    /// The sample an empty slot `slot` shows: round the samples again past
    /// the last.
    public static func sample(for slot: Int) -> Sample {
        all[((slot % all.count) + all.count) % all.count]
    }

    public static func sample(id: UUID) -> Sample? {
        all.first { $0.id == id }
    }
}
