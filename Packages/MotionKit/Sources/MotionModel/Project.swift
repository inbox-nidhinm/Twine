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
    /// Actions gathered under a name on the timeline, from any layers.
    /// Left out of the file while there are none.
    public var scenes: [TimelineScene]

    public init(composition: Composition = Composition(), layers: [Layer] = [], actions: [Action] = [],
                media: [MediaAsset] = [], scenes: [TimelineScene] = []) {
        self.composition = composition
        self.layers = layers
        self.actions = actions
        self.media = media
        self.scenes = scenes
    }

    private enum CodingKeys: String, CodingKey { case composition, layers, actions, media, scenes }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        composition = try c.decode(Composition.self, forKey: .composition)
        layers = try c.decode([Layer].self, forKey: .layers)
        actions = try c.decode([Action].self, forKey: .actions)
        media = try c.decode([MediaAsset].self, forKey: .media)
        scenes = try c.decodeIfPresent([TimelineScene].self, forKey: .scenes) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(composition, forKey: .composition)
        try c.encode(layers, forKey: .layers)
        try c.encode(actions, forKey: .actions)
        try c.encode(media, forKey: .media)
        if !scenes.isEmpty { try c.encode(scenes, forKey: .scenes) }
    }

    /// The scene an action is in, if any.
    public func scene(containing action: UUID) -> TimelineScene? {
        scenes.first { $0.actionIDs.contains(action) }
    }
}

/// Actions from any layers gathered under one name on the timeline, as a
/// moment of the animation ("Logo reveal"): its rows sit together under a
/// row of its own that shows how long it runs, folds, and moves or
/// stretches them all at once. An action is in at most one scene.
public struct TimelineScene: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var actionIDs: [UUID]

    public init(id: UUID = UUID(), name: String, actionIDs: [UUID]) {
        self.id = id
        self.name = name
        self.actionIDs = actionIDs
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
        max(1, FrameRate.whole((duration * frameRate.perSecond).rounded()))
    }

    /// The longest a composition or an action may run, and the furthest an
    /// action may start: a day, far past any motion design, and short of the
    /// numbers that stop being countable in frames.
    public static let longest: Double = 86_400
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
