import Foundation
import MotionModel

// Every template's recipe: its settings, and where its cards are at any
// point of its loop. A recipe is a plain function of its settings, the
// frame's size and the loop's `phase` (0 up to 1, ending where it began),
// so a template is the same on the canvas and in exports, and every setting
// stays live. `TemplateCards` turns what a recipe gives into the cards the
// frame draws.

/// What a setting measures, for the inspector's fields.
public enum TemplateUnit: Sendable, Equatable {
    case percent, degrees, count, plain
}

/// One of a choice's options.
public struct TemplateOption: Sendable, Equatable {
    public let key: String
    public let title: String
}

/// A setting a template shows in the inspector.
public struct TemplateControl: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case number(min: Double, max: Double, standard: Double, unit: TemplateUnit)
        case choice(options: [TemplateOption], standard: String)
    }

    public let key: String
    public let name: String
    public let kind: Kind
    public let help: String

    public var id: String { key }

    static func number(_ key: String, _ name: String, _ standard: Double, _ min: Double, _ max: Double,
                       _ unit: TemplateUnit, _ help: String) -> TemplateControl {
        TemplateControl(key: key, name: name, kind: .number(min: min, max: max, standard: standard, unit: unit), help: help)
    }

    static func choice(_ key: String, _ name: String, _ options: [(String, String)], _ help: String) -> TemplateControl {
        TemplateControl(key: key, name: name, kind: .choice(options: options.map { TemplateOption(key: $0.0, title: $0.1) },
                                                             standard: options[0].0), help: help)
    }
}

/// Where one card is: its cell (the box its picture is fitted into, in the
/// frame's pixels), its middle's place in the frame's space, and its turns.
/// `curve` is the radius of the circle each way it follows (0 is flat,
/// negative hollow), from which its bend is worked out once its size is
/// known.
public struct TemplateCard: Sendable, Equatable {
    public var index: Int
    public var cell: Size2
    public var position: Vec2
    public var z: Double
    public var rotation: Double
    public var tilt: Vec2
    public var curve: Vec2
    public var scale: Double
    public var opacity: Double
    /// The slot whose picture it shows; nil goes round them by `index`.
    public var slot: Int?
    /// A piece of a bigger picture: where that picture's whole area lies,
    /// in the card's own pixels from its top-left. The picture covers the
    /// area, and the card shows its part of it; the card is its cell
    /// exactly. Nil fits the whole picture to the card.
    public var area: Box?
    /// A plain colour in place of a picture, for a dimming veil or a glow.
    public var color: RGBA?
    /// Rounded as the template's cards are, or square, as a full frame is.
    public var rounded: Bool

    init(_ index: Int, cell: Size2, position: Vec2, z: Double = 0, rotation: Double = 0, tilt: Vec2 = .zero,
         curve: Vec2 = .zero, scale: Double = 1, opacity: Double = 1, slot: Int? = nil, area: Box? = nil,
         color: RGBA? = nil, rounded: Bool = true) {
        self.index = index
        self.cell = cell
        self.position = position
        self.z = z
        self.rotation = rotation
        self.tilt = tilt
        self.curve = curve
        self.scale = scale
        self.opacity = opacity
        self.slot = slot
        self.area = area
        self.color = color
        self.rounded = rounded
    }
}

/// A recipe's moment: the frame's camera and its cards.
public struct TemplateScene: Sendable, Equatable {
    public var space: Space3D
    public var cards: [TemplateCard]
}

public enum TemplateRecipes {
    /// How many slots a new template has.
    public static func slotCount(_ kind: TemplateKind) -> Int {
        switch kind {
        case .ringStream, .globe, .tiltedGlobe, .spiral, .depthStack, .orbit, .halo, .columnWall, .curvedWall: 12
        case .curvedCascade, .parallaxColumns, .tunnel, .carouselRing, .verticalRing, .photoLoop, .vortex, .wheel, .halfWheel: 8
        case .isoStream, .isoSpotlight: 10
        case .isoSwing: 9
        case .quadOrbit: 4
        case .zoomOrbit: 20
        default: flatSlotCount(kind)
        }
    }

    /// Where a new template rests in its loop, for Design and the
    /// picker's still: where it looks whole, past any building up.
    public static func restingPose(_ kind: TemplateKind) -> Double {
        switch kind {
        case .gridBuild: 0.7
        case .popTiles: 0.45
        case .stage: 0.16
        case .dropStack: 0.85
        case .burst: 0.12
        case .fannedDeck: 0.45
        case .flipTiles: 0.05
        default: 0
        }
    }

    // MARK: Settings

    private static let perspective = TemplateControl.number("perspective", "Perspective", 30, 5, 100, .percent,
                                                            "How strong the perspective is: higher brings the camera nearer.")
    private static let backs = TemplateControl.number("backFade", "Back fade", 60, 0, 100, .percent,
                                                      "How much fainter cards are with their backs to the camera.")
    private static let tilt = TemplateControl.number("tilt", "Tilt", -24, -80, 80, .degrees,
                                                     "Tips the whole scene towards or away from the camera.")
    private static func cards(_ standard: Double) -> TemplateControl {
        .number("cardSize", "Card size", standard, 5, 100, .percent, "How big each card is, as a share of the frame.")
    }
    private static func count(_ standard: Double, _ max: Double = 48) -> TemplateControl {
        .number("count", "Cards", standard, 3, max, .count, "How many cards it shows. It goes round the pictures again when there are more cards than pictures.")
    }
    private static func size(_ standard: Double) -> TemplateControl {
        .number("size", "Size", standard, 10, 200, .percent, "How big the whole arrangement is.")
    }
    private static let spinWay = TemplateControl.choice("direction", "Direction", [("forward", "Clockwise"), ("back", "Anticlockwise")],
                                                        "Which way it turns.")
    private static let stepping = TemplateControl.choice("motion", "Motion", [("continuous", "Continuous"), ("step", "Step per card")],
                                                         "Turns smoothly, or one card at a time with a pause on each.")
    private static let scroll = TemplateControl.choice("direction", "Direction", [("left", "Left"), ("right", "Right"), ("alternate", "Alternate")],
                                                       "Which way the rows run; Alternate runs every other row the other way.")
    private static let scrollUp = TemplateControl.choice("direction", "Direction", [("up", "Up"), ("down", "Down"), ("alternate", "Alternate")],
                                                         "Which way the columns run; Alternate runs every other column the other way.")
    private static let curvature = TemplateControl.number("curvature", "Curvature", -60, -100, 100, .percent,
                                                          "How far the wall curves: negative hollows it round you, positive bows it out.")
    private static let gap = TemplateControl.number("gap", "Gap", 6, 0, 50, .percent, "The space between cards, as a share of a card.")
    private static let edgeFade = TemplateControl.number("edgeFade", "Edge fade", 30, 0, 100, .percent, "How much the cards fade towards the edges.")
    private static let depthFade = TemplateControl.number("depthFade", "Depth fade", 45, 0, 100, .percent, "How much fainter cards are further away.")
    private static let pulse = TemplateControl.number("pulse", "Pulse", 40, 0, 100, .percent, "How much bigger a card grows as it comes to the front.")

    /// The settings a template shows, in order.
    public static func controls(_ kind: TemplateKind) -> [TemplateControl] {
        switch kind {
        case .ringStream:
            [count(12), tilt, size(80), cards(21), backs,
             .number("perspective", "Perspective", 18, 5, 100, .percent, "How strong the perspective is: higher brings the camera nearer.")]
        case .curvedWall:
            [.number("rows", "Rows", 3, 1, 6, .count, "How many rows of cards."), cards(26), curvature, gap, edgeFade, tilt, scroll]
        case .curvedCascade:
            [.number("columns", "Columns", 3, 1, 6, .count, "How many columns of cards."), cards(18), curvature, gap, edgeFade, tilt, scrollUp]
        case .columnWall:
            [.number("columns", "Columns", 5, 2, 9, .count, "How many columns of cards."), cards(30), curvature, gap, edgeFade, scrollUp]
        case .parallaxColumns:
            [.number("columns", "Columns", 5, 2, 9, .count, "How many columns of cards."), cards(26),
             .number("depth", "Parallax depth", 50, 0, 100, .percent, "How far apart the columns are in depth, so the near ones pass faster."),
             .number("variation", "Size variation", 30, 0, 80, .percent, "How much the cards' sizes differ."), gap]
        case .globe:
            [count(36, 80), size(70), cards(20), backs, tilt, spinWay]
        case .tiltedGlobe:
            [count(20, 80), size(50), cards(28), backs,
             .number("tilt", "Tilt", 27, -80, 80, .degrees, "Tips the globe towards or away from the camera."), spinWay]
        case .tunnel:
            [.number("size", "Tunnel size", 90, 30, 200, .percent, "How wide the tunnel is."),
             .number("length", "Card length", 55, 10, 100, .percent, "How long each card is along the tunnel."), gap, depthFade,
             .choice("direction", "Direction", [("forward", "Forward"), ("backward", "Backward")], "Whether the cards come towards you or go away.")]
        case .spiral:
            [count(24), .number("turns", "Turns", 3.75, 0.5, 8, .plain, "How many times the spiral winds round."), size(62), cards(26),
             .number("taper", "Taper", 0, 0, 90, .percent, "How much narrower the spiral gets towards its foot."), backs, tilt,
             .choice("direction", "Direction", [("down", "Downward"), ("up", "Upward")], "Which way the cards travel.")]
        case .depthStack:
            [count(24), cards(25), .number("depthGap", "Depth gap", 32, 5, 100, .percent, "How far apart the cards are in depth."),
             .number("spread", "Spread", 110, 0, 200, .percent, "How far the cards fan out from the middle."), depthFade,
             .choice("layout", "Layout", [("fan", "Fan"), ("scatter", "Scatter")], "Cards wound round in a fan, or scattered."),
             .choice("direction", "Direction", [("forward", "Forward"), ("backward", "Backward")], "Whether the cards come towards you or go away.")]
        case .carouselRing:
            [cards(37), .number("size", "Ring size", 131, 50, 300, .percent, "How big the ring is: at 100% its cards just touch."),
             perspective, backs, spinWay, stepping]
        case .verticalRing:
            [cards(37), .number("size", "Ring size", 131, 50, 300, .percent, "How big the ring is: at 100% its cards just touch."),
             perspective, backs,
             .choice("direction", "Direction", [("up", "Bottom to top"), ("down", "Top to bottom")], "Which way the ring turns."), stepping]
        case .isoStream:
            [cards(42), .number("spacing", "Spacing", 40, 0, 150, .percent, "The space between cards along the line."),
             .number("tilt", "Tilt", 60, 20, 80, .degrees, "How far the floor tips back."),
             .choice("direction", "Direction", [("upRight", "Up right"), ("downLeft", "Down left")], "Which way the line runs."),
             .choice("motion", "Motion", [("continuous", "Continuous"), ("step", "Stepped")], "Smoothly, or a card at a time.")]
        case .isoSpotlight:
            [cards(40), .number("spacing", "Spacing", 20, 0, 150, .percent, "The space between cards along the line."),
             .number("lift", "Lift", 50, 0, 200, .percent, "How far the card in the spotlight rises."),
             .number("tilt", "Tilt", 60, 20, 80, .degrees, "How far the floor tips back.")]
        case .isoSwing:
            [cards(34), .number("spacing", "Spacing", 18, 0, 100, .percent, "The space between cards."),
             .number("swing", "Swing angle", 30, 0, 90, .degrees, "How far the floor swings each way."),
             .number("float", "Float", 6, 0, 30, .percent, "How far the cards bob up and down."),
             .number("tilt", "Tilt", 55, 20, 80, .degrees, "How far the floor tips back."),
             .choice("motion", "Motion", [("swing", "Swing"), ("spin", "Full spin")], "Swings to and fro, or turns all the way round.")]
        case .orbit:
            [count(12), .number("width", "Ring width", 64, 10, 150, .percent, "How wide the orbit is."),
             .number("depth", "Ring depth", 26, 0, 100, .percent, "How deep the orbit is, front to back."), cards(22), pulse,
             .number("tilt", "Tilt", 0, -80, 80, .degrees, "Tips the orbit towards or away from the camera."), perspective, backs, spinWay]
        case .halo:
            [count(12), .number("width", "Ring width", 50, 10, 150, .percent, "How wide the orbit is."),
             .number("depth", "Ring depth", 25, 0, 100, .percent, "How deep the orbit is, front to back."), cards(24), pulse,
             .number("lean", "Lean to centre", 30, 0, 100, .percent, "How far the cards turn in towards the middle."),
             .number("tilt", "Tilt", -29, -80, 80, .degrees, "Tips the orbit towards or away from the camera."), perspective, backs, spinWay]
        case .quadOrbit:
            [.number("spread", "Spread", 70, 10, 150, .percent, "How far apart the cards travel."), cards(40), depthFade, spinWay]
        case .photoLoop:
            [count(8), .number("width", "Ring width", 56, 10, 150, .percent, "How wide the loop is."),
             .number("height", "Ring height", 56, 10, 150, .percent, "How tall the loop is."), cards(26), pulse, spinWay, stepping]
        case .zoomOrbit:
            [count(20), .number("stops", "Spin stops", 5, 1, 12, .count, "How many times it stops in one loop to look closer."),
             size(90), cards(18), .number("zoom", "Zoom", 140, 0, 400, .percent, "How much closer it comes at each stop."), spinWay]
        case .vortex:
            [.number("rings", "Rings", 3, 1, 6, .count, "How many rings of cards."), size(68), cards(15),
             .number("depth", "Depth", 50, 0, 150, .percent, "How far back each ring inside sits."), backs,
             .choice("direction", "Direction", [("forward", "Clockwise"), ("back", "Anticlockwise"), ("alternate", "Alternate")],
                     "Which way the rings turn; Alternate turns every other ring the other way.")]
        case .wheel:
            [count(8), size(92), cards(26), .number("turns", "Rotations", 1, 1, 6, .count, "How many times it goes round in one loop."), spinWay,
             .choice("motion", "Motion", [("continuous", "Continuous"), ("step", "Stepped")], "Smoothly, or a tick at a time."),
             .choice("spin", "Cards", [("follow", "Follow the wheel"), ("upright", "Stay upright"), ("flip", "Flip in 3D")],
                     "How the cards turn as the wheel goes round.")]
        case .halfWheel:
            [count(8), size(100), cards(20), .number("turns", "Rotations", 1, 1, 6, .count, "How many times it goes round in one loop."), spinWay,
             .choice("motion", "Motion", [("continuous", "Continuous"), ("step", "Stepped")], "Smoothly, or a tick at a time."),
             .choice("spin", "Cards", [("follow", "Follow the wheel"), ("upright", "Stay upright"), ("flip", "Flip in 3D")],
                     "How the cards turn as the wheel goes round.")]
        default:
            flatControls(kind)
        }
    }

    /// The settings read with their defaults.
    struct Settings {
        let values: [String: TemplateValue]
        let controls: [TemplateControl]

        /// Held to the setting's range, so a file from anywhere cannot ask
        /// for a billion cards.
        func n(_ key: String) -> Double {
            for c in controls where c.key == key {
                if case .number(let lo, let hi, let standard, _) = c.kind {
                    guard let v = values[key]?.number, v.isFinite else { return standard }
                    return min(max(v, lo), hi)
                }
            }
            return 0
        }

        /// A share: the number over 100.
        func f(_ key: String) -> Double { n(key) / 100 }

        func c(_ key: String) -> String {
            if let v = values[key]?.choice { return v }
            for c in controls where c.key == key { if case .choice(_, let standard) = c.kind { return standard } }
            return ""
        }

        func count(_ key: String = "count") -> Int { max(Int(n(key).rounded()), 1) }
    }

    // MARK: The scenes

    /// The template at `phase` in a frame of `size`.
    public static func scene(_ setup: TemplateSetup, phase: Double, size: Size2) -> TemplateScene {
        let s = Settings(values: setup.settings, controls: controls(setup.kind))
        let p = phase - phase.rounded(.down)
        let k = Kit(size: size)
        switch setup.kind {
        case .ringStream: return ringStream(s, p, k)
        case .curvedWall: return wall(s, p, k, vertical: false)
        case .curvedCascade: return wall(s, p, k, vertical: true)
        case .columnWall: return columns(s, p, k, parallax: false)
        case .parallaxColumns: return columns(s, p, k, parallax: true)
        case .globe, .tiltedGlobe: return globe(s, p, k)
        case .tunnel: return tunnel(s, p, k)
        case .spiral: return spiral(s, p, k)
        case .depthStack: return depthStack(s, p, k)
        case .carouselRing: return carousel(s, p, k, vertical: false, slots: max(setup.slots.count, 3))
        case .verticalRing: return carousel(s, p, k, vertical: true, slots: max(setup.slots.count, 3))
        case .isoStream: return isoStream(s, p, k, slots: max(setup.slots.count, 3))
        case .isoSpotlight: return isoSpotlight(s, p, k, slots: max(setup.slots.count, 3))
        case .isoSwing: return isoSwing(s, p, k)
        case .orbit, .halo: return orbit(s, p, k, halo: setup.kind == .halo)
        case .quadOrbit: return quadOrbit(s, p, k)
        case .photoLoop: return photoLoop(s, p, k)
        case .zoomOrbit: return zoomOrbit(s, p, k)
        case .vortex: return vortex(s, p, k)
        case .wheel, .halfWheel: return wheel(s, p, k, half: setup.kind == .halfWheel)
        default: return flatScene(setup.kind, s, p, k, slots: max(setup.slots.count, 1))
        }
    }

    /// The frame's measures, shared by every recipe.
    struct Kit {
        let size: Size2
        var w: Double { size.width }
        var h: Double { size.height }
        var u: Double { max(min(size.width, size.height), 1) }
        var centre: Vec2 { Vec2(size.width / 2, size.height / 2) }

        /// A camera whose strength `p` (0 to 1) brings it nearer.
        func camera(_ p: Double, backs: Double = 0, fade: Double = 0, orbit: Vec2 = .zero) -> Space3D {
            Space3D(distance: u * 0.6 / max(p, 0.05), depthFade: fade, backOpacity: 1 - min(max(backs, 0), 1), orbit: orbit)
        }

        /// A portrait cell `width` across.
        func cell(_ width: Double) -> Size2 { Size2(width, width * 4 / 3) }
    }

    static func rad(_ d: Double) -> Double { d * .pi / 180 }
    static func deg(_ r: Double) -> Double { r * 180 / .pi }
    /// Smooth's easing, for steps and swings.
    static func ease(_ u: Double) -> Double { Easing.default.progress(min(max(u, 0), 1)) }
    static func wrap(_ v: Double) -> Double { v - v.rounded(.down) }
    /// A loop's turn so far, `steps` stops in it with a pause on each, or
    /// smoothly when `steps` is nil.
    static func turned(_ p: Double, steps: Int?) -> Double {
        guard let steps, steps > 0 else { return p }
        let at = p * Double(steps)
        let k = at.rounded(.down), f = at - k
        // Each step moves in its first two thirds and rests in the last.
        return (k + ease(f / 0.66)) / Double(steps)
    }
    /// 1 inside, falling to 0 over `edge` at each end of 0...1, so cards
    /// coming round the end of a stream fade in and out of it.
    static func ends(_ s: Double, _ edge: Double = 0.08) -> Double {
        min(min(s / edge, (1 - s) / edge), 1)
    }

    /// A card on a ring of `radius` about the upright line through
    /// `middle`, at `angle` degrees round from the front, the ring tipped
    /// `tip` degrees on its level line: its place and its turn, facing out.
    static func onRing(_ angle: Double, radius: Double, tip: Double, middle: Vec3) -> (Vec2, Double, Vec2) {
        let a = rad(angle), t = rad(tip)
        let x = radius * sin(a), z0 = radius * cos(a)
        let y = -z0 * sin(t), z = z0 * cos(t)
        return (Vec2(middle.x + x, middle.y + y), middle.z + z, Vec2(tip, angle))
    }

    // MARK: 3D & Perspective

    private static func ringStream(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        // From the frame's shorter side, so it keeps whole in a wide frame.
        let n = s.count(), r = s.f("size") * k.u * 0.6, width = s.f("cardSize") * k.u
        let spin = -p * 360
        let cards = (0..<n).map { i -> TemplateCard in
            let (at, z, tilt) = onRing(Double(i) * 360 / Double(n) + spin, radius: r, tip: s.n("tilt"), middle: Vec3(k.centre.x, k.centre.y, 0))
            return TemplateCard(i, cell: k.cell(width), position: at, z: z, tilt: tilt, curve: Vec2(r, 0))
        }
        return TemplateScene(space: k.camera(s.f("perspective"), backs: s.f("backFade")), cards: cards)
    }

    /// Rows of cards on a curved wall, running across it (or columns
    /// running down it), going round again past its ends.
    private static func wall(_ s: Settings, _ p: Double, _ k: Kit, vertical: Bool) -> TemplateScene {
        let lines = s.count(vertical ? "columns" : "rows")
        let cellSide = s.f("cardSize") * (vertical ? k.w : k.h)
        let gap = 1 + s.f("gap")
        let cell = vertical ? Size2(cellSide * 4 / 3, cellSide) : Size2(cellSide * 4 / 3, cellSide)
        let pitch = (vertical ? cell.height : cell.width) * gap
        let across = (vertical ? cell.width : cell.height) * gap
        let span = (vertical ? k.h : k.w) * 1.6
        let perLine = max(Int((span / pitch).rounded(.up)) + 1, 2)
        let length = Double(perLine) * pitch
        let curvature = s.f("curvature")
        let radius = abs(curvature) > 0.01 ? (vertical ? k.h : k.w) / (abs(curvature) * .pi / 2) : 0
        let hollow = curvature < 0
        var cards: [TemplateCard] = []
        for line in 0..<lines {
            let offset = (Double(line) - Double(lines - 1) / 2) * across
            let way: Double
            switch s.c("direction") {
            case "right", "down": way = -1
            case "alternate": way = line % 2 == 0 ? 1 : -1
            default: way = 1
            }
            for j in 0..<perLine {
                // Along the wall from its middle, going round its length.
                var along = Double(j) * pitch - way * p * length
                along = wrap(along / length) * length - length / 2
                var x = along, z = 0.0, turn = 0.0
                if radius > 0 {
                    let theta = along / radius
                    x = radius * sin(theta)
                    z = (hollow ? 1 : -1) * radius * (1 - cos(theta))
                    turn = deg(hollow ? -theta : theta)
                }
                let fade = 1 - s.f("edgeFade") * min(abs(along) / (span / 2), 1)
                let position = vertical ? Vec2(k.centre.x + offset, k.centre.y + x) : Vec2(k.centre.x + x, k.centre.y + offset)
                // Upright walls turn on y; a cascade curves on its level line.
                let tilt = vertical ? Vec2(-turn, 0) : Vec2(0, turn)
                let curve = vertical ? Vec2(0, hollow ? -radius : radius) : Vec2(hollow ? -radius : radius, 0)
                cards.append(TemplateCard(line * perLine + j, cell: cell, position: position, z: z, tilt: tilt,
                                          curve: radius > 0 ? curve : .zero, opacity: max(fade, 0)))
            }
        }
        return TemplateScene(space: k.camera(0.35, orbit: Vec2(s.n("tilt"), 0)), cards: cards)
    }

    /// Upright columns of cards on a curve across the frame, each running
    /// up or down; with parallax, set at different depths and sizes.
    private static func columns(_ s: Settings, _ p: Double, _ k: Kit, parallax: Bool) -> TemplateScene {
        let n = s.count("columns")
        let gap = 1 + s.f("gap")
        let across = k.w * 0.9 / Double(n)
        let width = min(s.f("cardSize") * k.w * (parallax ? 0.5 : 0.4), across / gap)
        let pitch = width * 4 / 3 * gap
        let perColumn = max(Int((k.h * 1.6 / pitch).rounded(.up)) + 1, 2)
        let length = Double(perColumn) * pitch
        let curvature = parallax ? 0 : s.f("curvature")
        let radius = abs(curvature) > 0.01 ? k.w / (abs(curvature) * .pi / 2) : 0
        let hollow = curvature < 0
        var cards: [TemplateCard] = []
        for c in 0..<n {
            let across = (Double(c) - Double(n - 1) / 2) * (parallax ? across : width * gap)
            var x = across, z = 0.0, turn = 0.0
            if radius > 0 {
                let theta = across / radius
                x = radius * sin(theta)
                z = (hollow ? 1 : -1) * radius * (1 - cos(theta))
                turn = deg(hollow ? -theta : theta)
            }
            // A steady scatter: each column its own depth and size.
            let seed = Double((c * 7919) % 101) / 100
            let depth = parallax ? (seed - 0.5) * 2 * s.f("depth") * k.u * 1.5 : 0
            let grow = parallax ? 1 + (seed - 0.5) * 2 * s.f("variation") : 1
            let way: Double
            switch s.c("direction") {
            case "down": way = -1
            case "alternate": way = c % 2 == 0 ? 1 : -1
            default: way = 1
            }
            for j in 0..<perColumn {
                var down = Double(j) * pitch + Double(c) * pitch * 0.37 - way * p * length
                down = wrap(down / length) * length - length / 2
                let fade = parallax ? 1 : 1 - s.f("edgeFade") * min(abs(down) / (k.h * 0.8), 1)
                cards.append(TemplateCard(c * perColumn + j, cell: Size2(width * grow, width * grow * 4 / 3),
                                          position: Vec2(k.centre.x + x, k.centre.y + down), z: z + depth, tilt: Vec2(0, turn),
                                          curve: radius > 0 ? Vec2(hollow ? -radius : radius, 0) : .zero, opacity: max(fade, 0)))
            }
        }
        return TemplateScene(space: k.camera(0.35, fade: parallax ? 0.3 : 0), cards: cards)
    }

    /// Cards spread evenly over a sphere, facing out, the sphere turning.
    private static func globe(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let n = s.count(), r = s.f("size") * k.u / 2, width = s.f("cardSize") * k.u
        let golden = Double.pi * (3 - sqrt(5))
        let spin = (s.c("direction") == "back" ? 1 : -1) * p * 2 * .pi
        let tip = rad(s.n("tilt"))
        var cards: [TemplateCard] = []
        for i in 0..<n {
            let yv = 1 - 2 * (Double(i) + 0.5) / Double(n)
            let ring = sqrt(max(1 - yv * yv, 0))
            let theta = Double(i) * golden + spin
            // Where it sits and the way it faces, out from the middle.
            var normal = Vec3(ring * sin(theta), -yv, ring * cos(theta))
            normal = Vec3(normal.x, normal.y * cos(tip) - normal.z * sin(tip), normal.y * sin(tip) + normal.z * cos(tip))
            // A turn on y then on x that faces that way: Pose3D's order.
            let alpha = asin(min(max(normal.x, -1), 1))
            let beta = atan2(-normal.y, normal.z)
            cards.append(TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + r * normal.x, k.centre.y + r * normal.y),
                                      z: r * normal.z, tilt: Vec2(deg(beta), deg(alpha)), curve: Vec2(r, r)))
        }
        return TemplateScene(space: k.camera(0.4, backs: s.f("backFade")), cards: cards)
    }

    /// Cards along the four walls of a square tunnel, coming towards you.
    private static func tunnel(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let side = s.f("size") * k.u
        let length = s.f("length") * side
        let gap = 1 + s.f("gap")
        let pitch = length * gap
        let perLane = 8
        let depthSpan = Double(perLane) * pitch
        let way: Double = s.c("direction") == "backward" ? -1 : 1
        var cards: [TemplateCard] = []
        let lanes = [(-0.25), 0.25]
        for wall in 0..<4 {
            for (l, lane) in lanes.enumerated() {
                for j in 0..<perLane {
                    // From far down the tunnel up to just behind the camera.
                    let s0 = wrap((Double(j) + Double(wall) * 0.25 + Double(l) * 0.5) / Double(perLane) + way * p)
                    let z = side * 0.3 - s0 * depthSpan
                    let cell = Size2(length, side * 0.45)
                    let across = lane * side
                    // Each faces into the tunnel, its length along it: the
                    // side walls turned on their upright line, the ceiling
                    // and floor a quarter turn in their own plane, then
                    // tipped to lie flat.
                    let position: Vec2, tilt: Vec2, rotation: Double
                    switch wall {
                    case 0: position = Vec2(k.centre.x - side / 2, k.centre.y + across); tilt = Vec2(0, 90); rotation = 0
                    case 1: position = Vec2(k.centre.x + side / 2, k.centre.y + across); tilt = Vec2(0, -90); rotation = 0
                    case 2: position = Vec2(k.centre.x + across, k.centre.y - side / 2); tilt = Vec2(-90, 0); rotation = 90
                    default: position = Vec2(k.centre.x + across, k.centre.y + side / 2); tilt = Vec2(90, 0); rotation = 90
                    }
                    cards.append(TemplateCard((wall * 2 + l) * perLane + j, cell: cell, position: position, z: z,
                                              rotation: rotation, tilt: tilt, opacity: ends(s0, 0.1)))
                }
            }
        }
        var space = k.camera(0.6, fade: s.f("depthFade"))
        space.distance = side * 1.1
        return TemplateScene(space: space, cards: cards)
    }

    /// A winding helix of cards, travelling down (or up) it.
    private static func spiral(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let n = s.count(), turns = max(s.n("turns"), 0.25)
        let r = s.f("size") * k.u * 0.6, width = s.f("cardSize") * k.u * 0.7
        let span = s.f("size") * k.h * 1.2
        let way: Double = s.c("direction") == "up" ? -1 : 1
        let cards = (0..<n).map { i -> TemplateCard in
            let t = wrap(Double(i) / Double(n) + way * p)
            let radius = r * (1 - s.f("taper") * t)
            let (at, z, tilt) = onRing(t * turns * 360, radius: radius, tip: s.n("tilt"), middle: Vec3(k.centre.x, k.centre.y, 0))
            return TemplateCard(i, cell: k.cell(width), position: Vec2(at.x, at.y + (t - 0.5) * span), z: z, tilt: tilt,
                                curve: Vec2(radius, 0), opacity: ends(t))
        }
        return TemplateScene(space: k.camera(0.35, backs: s.f("backFade")), cards: cards)
    }

    /// Cards strung out in depth, coming towards you and fading through.
    private static func depthStack(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let n = s.count(), width = s.f("cardSize") * k.u
        let gap = s.f("depthGap") * k.u
        let span = Double(n) * gap
        let spread = s.f("spread") * k.u / 2
        let way: Double = s.c("direction") == "backward" ? -1 : 1
        let golden = Double.pi * (3 - sqrt(5))
        let cards = (0..<n).map { i -> TemplateCard in
            let t = wrap(Double(i) / Double(n) + way * p)
            let angle = s.c("layout") == "scatter" ? Double((i * 7919) % 360) * .pi / 180 : Double(i) * golden
            let reach = s.c("layout") == "scatter" ? spread * (0.3 + 0.7 * Double((i * 104729) % 100) / 100) : spread
            return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + reach * cos(angle), k.centre.y + reach * sin(angle) * 0.6),
                                z: k.u * 0.4 - t * span, opacity: ends(t, 0.12))
        }
        return TemplateScene(space: k.camera(0.5, fade: s.f("depthFade")), cards: cards)
    }

    /// A great ring of cards facing out, its nearest card in the middle of
    /// the frame, turning smoothly or a card at a time.
    private static func carousel(_ s: Settings, _ p: Double, _ k: Kit, vertical: Bool, slots: Int) -> TemplateScene {
        let n = slots
        let width = s.f("cardSize") * k.u
        // Its circumference is its cards side by side at 100%.
        let r = s.f("size") * Double(n) * width * (vertical ? 4.0 / 3 : 1) / (2 * .pi)
        let back: Bool = s.c("direction") == "back" || s.c("direction") == "down"
        let turn = turned(p, steps: s.c("motion") == "step" ? n : nil) * 360 * (back ? 1 : -1)
        let cards = (0..<n).map { i -> TemplateCard in
            let a = Double(i) * 360 / Double(n) + turn
            let x = r * sin(rad(a)), z = r * cos(rad(a)) - r
            if vertical {
                return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x, k.centre.y - x), z: z, tilt: Vec2(a, 0))
            }
            return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + x, k.centre.y), z: z, tilt: Vec2(0, a))
        }
        return TemplateScene(space: k.camera(s.f("perspective"), backs: s.f("backFade")), cards: cards)
    }

    // MARK: Isometric

    /// An isometric camera looking down on a floor tipped back `tilt`
    /// degrees, the cards turned on it as tiles are.
    private static func iso(_ tilt: Double, orbit y: Double = 0) -> Space3D {
        Space3D(isIsometric: true, orbit: Vec2(tilt, y))
    }

    private static func isoStream(_ s: Settings, _ p: Double, _ k: Kit, slots: Int) -> TemplateScene {
        let n = max(slots, 6), width = s.f("cardSize") * k.u * 0.7
        let pitch = width * (1 + s.f("spacing"))
        let length = Double(n) * pitch
        let way: Double = s.c("direction") == "downLeft" ? -1 : 1
        let along = turned(p, steps: s.c("motion") == "step" ? n : nil)
        let cards = (0..<n).map { i -> TemplateCard in
            let t = wrap(Double(i) / Double(n) + way * along)
            let d = (t - 0.5) * length
            return TemplateCard(i, cell: Size2(width, width), position: Vec2(k.centre.x + d * 0.7071, k.centre.y - d * 0.7071),
                                rotation: 45, opacity: ends(t, 0.1))
        }
        return TemplateScene(space: iso(s.n("tilt")), cards: cards)
    }

    private static func isoSpotlight(_ s: Settings, _ p: Double, _ k: Kit, slots: Int) -> TemplateScene {
        let n = max(slots, 3), width = s.f("cardSize") * k.u * 0.6
        let pitch = width * (1 + s.f("spacing"))
        let focus = turned(p, steps: n) * Double(n)
        let cards = (0..<n).map { i -> TemplateCard in
            // Wound round the line so it goes on without an end.
            var d = Double(i) - focus
            d -= (d / Double(n)).rounded() * Double(n)
            let near = max(1 - abs(d), 0)
            let x = d * pitch
            return TemplateCard(i, cell: Size2(width, width), position: Vec2(k.centre.x + x * 0.7071, k.centre.y - x * 0.7071),
                                z: near * s.f("lift") * width, rotation: 45, scale: 1 + near * 0.25,
                                opacity: min(max(Double(n) / 2 - abs(d), 0), 1))
        }
        return TemplateScene(space: iso(s.n("tilt")), cards: cards)
    }

    private static func isoSwing(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let width = s.f("cardSize") * k.u * 0.7
        let pitch = width * (1 + s.f("spacing"))
        let swing = s.c("motion") == "spin" ? p * 360 : sin(p * 2 * .pi) * s.n("swing")
        let a = rad(swing)
        var cards: [TemplateCard] = []
        for row in 0..<3 {
            for col in 0..<3 {
                let i = row * 3 + col
                let bob = sin((p + Double(i) / 9) * 2 * .pi) * s.f("float") * k.u
                // The floor turns about its own middle, in its plane, before
                // the camera's tip lays it back.
                let x = Double(col - 1) * pitch, y = Double(row - 1) * pitch
                cards.append(TemplateCard(i, cell: Size2(width, width),
                                          position: Vec2(k.centre.x + x * cos(a) - y * sin(a), k.centre.y + x * sin(a) + y * cos(a)),
                                          z: bob, rotation: 45 + swing))
            }
        }
        return TemplateScene(space: iso(s.n("tilt")), cards: cards)
    }

    // MARK: Orbit

    /// Cards round an oval that turns, each facing the camera, the front
    /// one grown by the pulse.
    private static func orbit(_ s: Settings, _ p: Double, _ k: Kit, halo: Bool) -> TemplateScene {
        let n = s.count(), rw = s.f("width") * k.w / 2, rd = s.f("depth") * k.u
        let width = s.f("cardSize") * k.u
        let spin = (s.c("direction") == "back" ? 1 : -1) * p * 360
        let tip = rad(s.n("tilt"))
        let cards = (0..<n).map { i -> TemplateCard in
            let a = rad(Double(i) * 360 / Double(n) + spin)
            let x = rw * sin(a), z0 = rd * cos(a)
            let y = -z0 * sin(tip), z = z0 * cos(tip)
            let front = (cos(a) + 1) / 2
            let lean = halo ? deg(a) * s.f("lean") : 0
            return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + x, k.centre.y + y), z: z,
                                tilt: Vec2(halo ? s.n("tilt") * 0.5 : 0, lean), scale: 1 + s.f("pulse") * pow(front, 3) * 0.6)
        }
        return TemplateScene(space: k.camera(s.f("perspective"), backs: s.f("backFade"), fade: 0.3), cards: cards)
    }

    private static func quadOrbit(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let rw = s.f("spread") * k.w / 2, rd = s.f("spread") * k.u * 0.6
        let width = s.f("cardSize") * k.u
        let spin = (s.c("direction") == "back" ? 1 : -1) * p * 360
        let cards = (0..<4).map { i -> TemplateCard in
            let a = rad(Double(i) * 90 + spin)
            return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + rw * sin(a), k.centre.y), z: rd * cos(a) - rd)
        }
        return TemplateScene(space: k.camera(0.5, fade: s.f("depthFade")), cards: cards)
    }

    /// Cards round a loop in the frame's own plane, upright, the top one
    /// grown by the pulse.
    private static func photoLoop(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let n = s.count(), rw = s.f("width") * k.w / 2, rh = s.f("height") * k.h / 2
        let width = s.f("cardSize") * k.u
        let turn = turned(p, steps: s.c("motion") == "step" ? n : nil) * 360 * (s.c("direction") == "back" ? -1 : 1)
        let cards = (0..<n).map { i -> TemplateCard in
            let a = rad(Double(i) * 360 / Double(n) + turn)
            let top = (cos(a) + 1) / 2
            return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + rw * sin(a), k.centre.y - rh * cos(a)),
                                z: top * width * 0.5, scale: 1 + s.f("pulse") * pow(top, 4) * 0.6)
        }
        return TemplateScene(space: k.camera(0.4), cards: cards)
    }

    /// A ring of cards in the frame's plane that turns, stops, and comes
    /// closer to look, `stops` times a loop.
    private static func zoomOrbit(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let n = s.count(), stops = s.count("stops")
        let r = s.f("size") * k.u / 2, width = s.f("cardSize") * k.u
        let at = p * Double(stops)
        let step = at.rounded(.down), f = at - step
        let turn = (step + ease(f / 0.45)) / Double(stops) * 360 * (s.c("direction") == "back" ? -1 : 1)
        // Comes in while it rests, and goes back before the next turn.
        let zoom = f > 0.45 ? sin((f - 0.45) / 0.55 * .pi) : 0
        let cards = (0..<n).map { i -> TemplateCard in
            let a = rad(Double(i) * 360 / Double(n) + turn)
            return TemplateCard(i, cell: k.cell(width), position: Vec2(k.centre.x + r * sin(a), k.centre.y - r * cos(a)),
                                z: zoom * s.f("zoom") * k.u * 0.45)
        }
        return TemplateScene(space: k.camera(0.5), cards: cards)
    }

    /// Rings of cards one inside another, further back each, turning.
    private static func vortex(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let rings = s.count("rings")
        let outer = s.f("size") * k.u / 2, width = s.f("cardSize") * k.u
        var cards: [TemplateCard] = []
        var index = 0
        for ring in 0..<rings {
            let r = outer * Double(rings - ring) / Double(rings)
            let n = max(Int((2 * .pi * r / (width * 1.25)).rounded(.down)), 3)
            let way: Double
            switch s.c("direction") {
            case "back": way = -1
            case "alternate": way = ring % 2 == 0 ? 1 : -1
            default: way = 1
            }
            for j in 0..<n {
                let a = Double(j) * 360 / Double(n) + way * p * 360
                cards.append(TemplateCard(index, cell: k.cell(width),
                                          position: Vec2(k.centre.x + r * sin(rad(a)), k.centre.y - r * cos(rad(a))),
                                          z: -Double(ring) * s.f("depth") * k.u * 0.5, rotation: a))
                index += 1
            }
        }
        return TemplateScene(space: k.camera(0.45, backs: s.f("backFade"), fade: 0.25), cards: cards)
    }

    /// A great wheel of cards turning in the frame's plane; the half wheel
    /// rises from under the frame's foot.
    private static func wheel(_ s: Settings, _ p: Double, _ k: Kit, half: Bool) -> TemplateScene {
        let n = s.count(), width = s.f("cardSize") * k.u
        let r = half ? s.f("size") * k.w / 2 : s.f("size") * k.h / 2
        let hub = half ? Vec2(k.centre.x, k.h + r * 0.2) : k.centre
        let steps = s.c("motion") == "step" ? n * s.count("turns") : nil
        let turn = turned(p, steps: steps) * 360 * Double(s.count("turns")) * (s.c("direction") == "back" ? -1 : 1)
        let cards = (0..<n).map { i -> TemplateCard in
            let a = Double(i) * 360 / Double(n) + turn
            let position = Vec2(hub.x + r * sin(rad(a)), hub.y - r * cos(rad(a)))
            switch s.c("spin") {
            case "upright": return TemplateCard(i, cell: k.cell(width), position: position)
            case "flip": return TemplateCard(i, cell: k.cell(width), position: position, tilt: Vec2(0, a))
            default: return TemplateCard(i, cell: k.cell(width), position: position, rotation: a)
            }
        }
        return TemplateScene(space: k.camera(0.4, backs: 0.5), cards: cards)
    }
}
