import Foundation

/// Everything in one `.twine` file except the media bytes themselves.
public struct Project: Codable, Sendable, Equatable {
    public var composition: Composition
    /// Top-level layers, drawn in array order: the last one is in front. The
    /// layers panel shows them reversed, front at the top, as every design
    /// tool does.
    public var layers: [Layer]
    /// Every action, in no particular order. Each names the layer it acts on;
    /// the timeline sorts them for display.
    public var actions: [Action]
    /// Every file copied into the package's `media` folder.
    public var media: [MediaAsset]

    public init(composition: Composition = Composition(), layers: [Layer] = [], actions: [Action] = [],
                media: [MediaAsset] = []) {
        self.composition = composition
        self.layers = layers
        self.actions = actions
        self.media = media
    }
}

/// The one scene a project has.
public struct Composition: Codable, Sendable, Equatable {
    public var width: Int
    public var height: Int
    public var frameRate: FrameRate
    /// Seconds.
    public var duration: Double
    public var background: Background

    public init(width: Int = 1920, height: Int = 1080, frameRate: FrameRate = .fps60,
                duration: Double = 5, background: Background = Background()) {
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.duration = duration
        self.background = background
    }

    public var size: Size2 { Size2(Double(width), Double(height)) }

    /// How many frames the composition runs. A duration that does not land on
    /// a frame boundary is rounded to the nearest one, and there is always at
    /// least one frame to show.
    public var frameCount: Int {
        max(1, Int((duration * frameRate.perSecond).rounded()))
    }
}

/// The composition's ground. Transparency is a switch beside the colour rather
/// than a colour of its own, so turning it off brings the old colour back.
public struct Background: Codable, Sendable, Equatable {
    public var color: RGBA
    public var isTransparent: Bool

    public init(color: RGBA = .white, isTransparent: Bool = false) {
        self.color = color
        self.isTransparent = isTransparent
    }
}

/// A file copied into the package. Layers refer to it by `id`; the file on disk
/// is `media/<fileName>`.
public struct MediaAsset: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var kind: MediaKind
    /// The name inside the package, which is the id plus the original
    /// extension, so two imports called `clip.mov` cannot collide.
    public var fileName: String
    /// What the file was called where it came from, for naming its layer.
    public var originalName: String
    /// SHA-256 of the file's bytes. Importing the same file again reuses the
    /// copy already in the package rather than storing it twice.
    public var contentHash: String
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    /// Seconds, for video and audio.
    public var duration: Double?
    public var hasAudio: Bool

    public init(id: UUID = UUID(), kind: MediaKind, fileName: String, originalName: String,
                contentHash: String, pixelWidth: Int? = nil, pixelHeight: Int? = nil,
                duration: Double? = nil, hasAudio: Bool = false) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.originalName = originalName
        self.contentHash = contentHash
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.hasAudio = hasAudio
    }
}

public enum MediaKind: String, Codable, Sendable {
    case image, video, audio
}
