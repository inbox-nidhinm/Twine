import Foundation

/// A whole scene of cards from a list of pictures: a ring that turns, a
/// globe, a tunnel. A template lives on a frame (`GroupContent.template`):
/// the frame holds its slots and settings, and its cards are worked out
/// each moment from the template's recipe (`TemplateRecipes`, in
/// MotionEvaluation), so every setting stays live. Its bar on the timeline
/// (`ActionSpec.template`) says when it plays. Split into Layers turns it
/// into an ordinary frame in 3D of cards and actions.
public struct TemplateSetup: Codable, Sendable, Equatable {
    public var kind: TemplateKind
    /// The pictures, in order; nil is an empty slot, drawn as a plain card.
    /// Templates with more cards than slots go round the slots again.
    public var slots: [UUID?]
    /// The template's own settings, by their keys; a setting not here is
    /// the recipe's default.
    public var settings: [String: TemplateValue]
    /// The cards' shape: their pictures' own, or one for all.
    public var ratio: CardRatio
    /// Rounding, as a share of a card's shorter side.
    public var cornerRadius: Double
    /// A soft shadow under every card.
    public var shadow: Bool
    /// Where in its loop it rests, 0 to 1: what Design shows, and what
    /// shows before and after its bar.
    public var pose: Double

    public init(kind: TemplateKind, slots: [UUID?], settings: [String: TemplateValue] = [:], ratio: CardRatio = .auto,
                cornerRadius: Double = 0.06, shadow: Bool = false, pose: Double = 0) {
        self.kind = kind
        self.slots = slots
        self.settings = settings
        self.ratio = ratio
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.pose = pose
    }

    private enum CodingKeys: String, CodingKey { case kind, slots, settings, ratio, cornerRadius, shadow, pose }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decode(TemplateKind.self, forKey: .kind)
        slots = try c.decodeIfPresent([UUID?].self, forKey: .slots) ?? []
        settings = try c.decodeIfPresent([String: TemplateValue].self, forKey: .settings) ?? [:]
        ratio = try c.decodeIfPresent(CardRatio.self, forKey: .ratio) ?? .auto
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0.06
        shadow = try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? false
        pose = try c.decodeIfPresent(Double.self, forKey: .pose) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(slots, forKey: .slots)
        if !settings.isEmpty { try c.encode(settings, forKey: .settings) }
        if ratio != .auto { try c.encode(ratio, forKey: .ratio) }
        try c.encode(cornerRadius, forKey: .cornerRadius)
        if shadow { try c.encode(shadow, forKey: .shadow) }
        if pose != 0 { try c.encode(pose, forKey: .pose) }
    }

    /// Every picture the template shows.
    public var mediaIDs: [UUID] { slots.compactMap { $0 } }
}

/// A setting's value: a number, or one of a choice's options by its key.
public enum TemplateValue: Codable, Sendable, Equatable {
    case number(Double)
    case choice(String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .choice(try c.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let n): try c.encode(n)
        case .choice(let s): try c.encode(s)
        }
    }

    public var number: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    public var choice: String? {
        if case .choice(let s) = self { return s }
        return nil
    }
}

/// The shape every card takes: its own picture's, or one for all.
public enum CardRatio: String, Codable, Sendable, CaseIterable {
    case auto
    case square = "1:1"
    case landscape43 = "4:3"
    case portrait34 = "3:4"
    case portrait45 = "4:5"
    case wide = "16:9"
    case tall = "9:16"

    /// Width over height; nil for a picture's own.
    public var aspect: Double? {
        switch self {
        case .auto: nil
        case .square: 1
        case .landscape43: 4.0 / 3
        case .portrait34: 3.0 / 4
        case .portrait45: 4.0 / 5
        case .wide: 16.0 / 9
        case .tall: 9.0 / 16
        }
    }

    public var title: String { self == .auto ? "Auto" : rawValue }
}

/// Every template there is. The raw values are what files store. The
/// names are Twine's own; `docs/templates.md` says which Animos template
/// each answers.
public enum TemplateKind: String, Codable, Sendable, CaseIterable {
    // 3D & Perspective
    case ringStream = "ring-stream", curvedWall = "curved-wall", globe, tiltedGlobe = "tilted-globe"
    case curvedCascade = "curved-cascade", columnWall = "column-wall", parallaxColumns = "parallax-columns"
    case tunnel, spiral, depthStack = "depth-stack", carouselRing = "carousel-ring", verticalRing = "vertical-ring"
    // Isometric
    case isoStream = "iso-stream", isoSpotlight = "iso-spotlight", isoSwing = "iso-swing"
    // Orbit
    case orbit, halo, quadOrbit = "quad-orbit", photoLoop = "photo-loop", zoomOrbit = "zoom-orbit"
    case vortex, wheel, halfWheel = "half-wheel"
}

/// When a template plays: its bar holds `loops` turns of the template's
/// loop, so stretching the bar slows it, and it ends where it began.
public struct TemplatePlay: Codable, Sendable, Equatable {
    public var loops: Double

    public init(loops: Double = 1) {
        self.loops = loops
    }
}

extension Layer {
    /// A template frame's setup, or nil for anything else. Setting it on
    /// anything but a frame does nothing.
    public var template: TemplateSetup? {
        get {
            if case .group(let g) = content { return g.template }
            return nil
        }
        set {
            guard case .group(var g) = content, g.frame != nil else { return }
            g.template = newValue
            content = .group(g)
        }
    }

    public var isTemplate: Bool { template != nil }
}
