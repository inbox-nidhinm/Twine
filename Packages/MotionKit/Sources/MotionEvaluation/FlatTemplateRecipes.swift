import Foundation
import MotionModel

// The flat and nearly flat templates (`docs/templates.md`, milestone 6):
// Carousel & Flow, Grid, Spotlight & Focus, Reveal & Wipe and Stack &
// Scatter. Most step from one picture to the next, a step a picture, so
// each loop ends where it began; pieces of a picture (tiles, strips, a
// slow zoom) are cards with an `area`.

extension TemplateRecipes {
    static func flatSlotCount(_ kind: TemplateKind) -> Int {
        switch kind {
        case .curvedColumn, .filmRoll, .swingWheel, .diagonalRun, .popTiles, .shuffle: 6
        case .flow, .verticalFlow, .slideCarousel: 5
        case .focusSlide, .flipTiles, .fannedDeck, .toss: 8
        case .brickMarquee: 10
        case .featureReel: 7
        case .gridBuild, .gridZoom, .railFocus, .peelDeck, .split, .tileWipe, .slideStack, .dropStack, .burst: 4
        case .ticker, .tiltedTicker, .driftColumns, .feed, .trail: 12
        case .stage, .slowZoom, .angledWipe, .stripes: 3
        default: sequenceSlotCount(kind)
        }
    }

    // MARK: Settings

    private static func size(_ standard: Double) -> TemplateControl {
        .number("cardSize", "Card size", standard, 5, 100, .percent, "How big each card is, as a share of the frame.")
    }
    private static func gapControl(_ standard: Double) -> TemplateControl {
        .number("gap", "Gap", standard, 0, 50, .percent, "The space between cards, as a share of a card.")
    }
    private static let flowWay = TemplateControl.choice("direction", "Direction", [("forward", "Right to left"), ("back", "Left to right")],
                                                        "Which way the cards travel.")
    private static let flowWayUp = TemplateControl.choice("direction", "Direction", [("forward", "Bottom to top"), ("back", "Top to bottom")],
                                                          "Which way the cards travel.")
    private static let stopping = TemplateControl.choice("motion", "Motion", [("stop", "Stop at centre"), ("continuous", "Continuous")],
                                                         "Stops on each card in the middle, or runs on.")
    private static let axis = TemplateControl.choice("axis", "Direction", [("horizontal", "Across"), ("vertical", "Down")],
                                                     "Which way it runs.")
    private static let shadowless = TemplateControl.number("cardSize", "Card size", 80, 20, 100, .percent,
                                                           "How big the cards are, as a share of the frame.")
    private static let curve = TemplateControl.number("curve", "3D curve", 70, -100, 100, .percent,
                                                      "How far the strip curves away in depth: negative hollows it.")

    static func flatControls(_ kind: TemplateKind) -> [TemplateControl] {
        switch kind {
        case .curvedColumn: [size(34), gapControl(3), curve, stopping]
        case .filmRoll: [size(32), gapControl(3), curve, stopping]
        case .swingWheel:
            [size(70), .number("wheel", "Wheel size", 105, 40, 300, .percent, "How big the wheel is."),
             .number("anticipation", "Anticipation", 20, 0, 100, .percent, "How far it pulls back before each turn."),
             .number("overshoot", "Overshoot", 10, 0, 100, .percent, "How far it swings past before settling."),
             .number("hold", "Hold", 33, 0, 90, .percent, "How long it rests on each card."), flowWay]
        case .flow:
            [size(46), gapControl(10), .number("sideTilt", "Side tilt", 40, 0, 85, .degrees, "How far the cards to the sides turn away."),
             flowWay, stopping]
        case .verticalFlow:
            [size(40), gapControl(10), .number("sideTilt", "Side tilt", 40, 0, 85, .degrees, "How far the cards above and below turn away."),
             flowWayUp, stopping]
        case .slideCarousel:
            [size(44), gapControl(8), .number("sideScale", "Side cards", 82, 30, 100, .percent, "How big the cards to the sides are."), axis]
        case .diagonalRun:
            [size(40), .number("overlap", "Overlap", 55, 0, 90, .percent, "How far each card lies over the next."),
             .choice("direction", "Direction", [("downRight", "Down right"), ("upRight", "Up right")], "Which way the line runs."),
             .choice("motion", "Motion", [("continuous", "Continuous"), ("step", "Stepped")], "Smoothly, or a card at a time.")]
        case .focusSlide:
            [size(30), .number("centreScale", "Centre size", 170, 100, 300, .percent, "How big the card in the middle grows."),
             .number("zigzag", "Zigzag", 30, 0, 100, .percent, "How far the cards step up and down."), gapControl(10), axis]
        case .brickMarquee:
            [.number("rows", "Rows", 3, 1, 6, .count, "How many rows of cards."), gapControl(4),
             .choice("layout", "Layout", [("one", "Layout 1"), ("two", "Layout 2"), ("three", "Layout 3")], "The pattern of wide and narrow cards."),
             .choice("direction", "Direction", [("left", "Left"), ("right", "Right")], "Which way the rows run.")]
        case .featureReel:
            [size(18), .number("lift", "Active lift", 40, 0, 100, .percent, "How far the card in play rises."),
             .number("heroOpacity", "Hero", 55, 0, 100, .percent, "How strongly the card in play shows behind, filling the frame."),
             .number("zoom", "Slow zoom", 8, 0, 40, .percent, "How far the picture behind zooms in as it plays.")]
        case .gridBuild:
            [gapControl(4), .choice("order", "Order", [("rows", "Rows"), ("columns", "Columns"), ("diagonal", "Diagonal")],
                                    "The order the tiles come in.")]
        case .gridZoom:
            [gapControl(4), .number("dim", "Background dim", 45, 0, 100, .percent, "How much the other tiles darken while one is up close.")]
        case .flipTiles: [gapControl(4), axis]
        case .popTiles: [gapControl(4), .number("visible", "Shown", 62, 20, 95, .percent, "How much of the loop the tiles stay up.")]
        case .ticker:
            [.number("rows", "Rows", 3, 1, 6, .count, "How many rows of cards."), size(30),
             .number("tilt", "Tilt", -6, -45, 45, .degrees, "Turns the rows across the frame."), gapControl(6),
             .choice("flow", "Flow", [("opposed", "Opposed"), ("same", "Same way")], "Whether every other row runs the other way.")]
        case .tiltedTicker:
            [.number("rows", "Rows", 3, 1, 6, .count, "How many rows of cards."), size(28),
             .number("tilt", "Tilt", 30, 0, 75, .degrees, "How far the rows lie back."), gapControl(6),
             .choice("flow", "Flow", [("opposed", "Opposed"), ("same", "Same way")], "Whether every other row runs the other way.")]
        case .driftColumns: [.number("columns", "Columns", 4, 2, 8, .count, "How many columns of cards."), gapControl(4)]
        case .feed: [size(52), gapControl(8), .choice("motion", "Motion", [("flick", "Flicks"), ("steady", "Steady")], "A card at a time, or smoothly.")]
        case .stage:
            [size(70), .number("travel", "Travel", 60, 0, 150, .percent, "How far each card travels on and off."),
             .number("trail", "Ghost trail", 3, 0, 6, .count, "How many fading copies follow each card.")]
        case .railFocus: [.number("rail", "Rail size", 26, 10, 45, .percent, "How wide the rail of small cards is."), gapControl(4)]
        case .peelDeck: [size(48), .number("peek", "Stack peek", 4, 0, 20, .percent, "How much of each card below shows.")]
        case .slowZoom:
            [.number("zoom", "Zoom", 12, 0, 50, .percent, "How far each picture zooms in."),
             .choice("pan", "Pan", [("alternate", "Alternate"), ("left", "Left"), ("right", "Right")], "Which way each picture drifts.")]
        case .angledWipe:
            [.number("angle", "Edge angle", -20, -60, 60, .degrees, "How far the wiping edge leans."),
             .number("glow", "Edge glow", 60, 0, 100, .percent, "How bright the line along the wiping edge is.")]
        case .stripes: [.number("strips", "Strips", 7, 2, 24, .count, "How many strips the picture comes in as.")]
        case .split: [.number("ratio", "Split", 50, 10, 90, .percent, "Where the picture splits."), gapControl(2)]
        case .tileWipe:
            [.number("rows", "Rows", 4, 1, 10, .count, "How many rows of tiles."), .number("columns", "Columns", 4, 1, 10, .count, "How many columns of tiles."),
             .choice("pattern", "Pattern", [("normal", "In order"), ("diagonal", "Diagonal"), ("radial", "Radial"), ("random", "Random")],
                     "The order the tiles come in.")]
        case .slideStack: [shadowless, .number("depthScale", "Depth scale", 95, 70, 100, .percent, "How much smaller each card below is.")]
        case .dropStack: [size(70), .number("spin", "Rotation", 100, 0, 200, .percent, "How much the cards land askew.")]
        case .fannedDeck:
            [size(60), .number("overlap", "Overlap", 70, 0, 95, .percent, "How far each card lies over the next."),
             .choice("motion", "Motion", [("each", "One by one"), ("together", "All together")], "Whether the cards fan out in turn or at once.")]
        case .trail: [size(20), .number("length", "Trail length", 10, 2, 24, .count, "How many cards the trail holds.")]
        case .burst: [.choice("flow", "Flow", [("each", "One by one"), ("volley", "Volley")], "One card at a time, or all at once.")]
        case .toss:
            [size(26), .number("height", "Throw height", 75, 10, 100, .percent, "How high the cards are thrown."),
             .number("spin", "Spin", 12, 0, 90, .degrees, "How far the cards turn as they fly.")]
        case .shuffle: [size(28), gapControl(10)]
        default: sequenceControls(kind)
        }
    }

    // MARK: Scenes

    static func flatScene(_ kind: TemplateKind, _ s: Settings, _ p: Double, _ k: Kit, slots: Int) -> TemplateScene {
        let n = max(slots, 1)
        switch kind {
        case .curvedColumn: return strip(s, p, k, n, vertical: true)
        case .filmRoll: return strip(s, p, k, n, vertical: false)
        case .swingWheel: return swingWheel(s, p, k, n)
        case .flow: return flow(s, p, k, n, vertical: false)
        case .verticalFlow: return flow(s, p, k, n, vertical: true)
        case .slideCarousel: return slideCarousel(s, p, k, n)
        case .diagonalRun: return diagonalRun(s, p, k, n)
        case .focusSlide: return focusSlide(s, p, k, n)
        case .brickMarquee: return brickMarquee(s, p, k)
        case .featureReel: return featureReel(s, p, k, n)
        case .gridBuild: return gridBuild(s, p, k, n)
        case .gridZoom: return gridZoom(s, p, k, n)
        case .flipTiles: return flipTiles(s, p, k, n)
        case .popTiles: return popTiles(s, p, k, n)
        case .ticker: return ticker(s, p, k, tilted: false)
        case .tiltedTicker: return ticker(s, p, k, tilted: true)
        case .driftColumns: return driftColumns(s, p, k)
        case .feed: return feed(s, p, k, n)
        case .stage: return stage(s, p, k, n)
        case .railFocus: return railFocus(s, p, k, n)
        case .peelDeck: return peelDeck(s, p, k, n)
        case .slowZoom: return slowZoom(s, p, k, n)
        case .angledWipe: return angledWipe(s, p, k, n)
        case .stripes: return stripes(s, p, k, n)
        case .split: return split(s, p, k, n)
        case .tileWipe: return tileWipe(s, p, k, n)
        case .slideStack: return slideStack(s, p, k, n)
        case .dropStack: return dropStack(s, p, k, n)
        case .fannedDeck: return fannedDeck(s, p, k, n)
        case .trail: return trail(s, p, k, n)
        case .burst: return burst(s, p, k, n)
        case .toss: return toss(s, p, k, n)
        case .shuffle: return shuffle(s, p, k, n)
        default: return sequenceScene(kind, s, p, k, slots: slots)
        }
    }

    /// A flat camera: far off, so nothing at depth 0 changes.
    private static func flat(_ k: Kit) -> Space3D { Space3D(distance: k.u * 4) }

    /// Which step of `n` a loop is on, and how far through it.
    private static func step(_ p: Double, _ n: Int) -> (Int, Double) {
        let at = p * Double(n)
        let i = at.rounded(.down)
        return (Int(i) % max(n, 1), at - i)
    }

    /// The whole frame as a box.
    private static func frameBox(_ k: Kit) -> Box { Box(origin: .zero, size: k.size) }

    /// A card showing the part `rect` (in the frame) of picture `slot`
    /// laid over the whole frame.
    private static func piece(_ index: Int, slot: Int, _ rect: Box, _ k: Kit, opacity: Double = 1, scale: Double = 1,
                              offset: Vec2 = .zero) -> TemplateCard {
        TemplateCard(index, cell: Size2(rect.width, rect.height), position: rect.center + offset, scale: scale, opacity: opacity,
                     slot: slot, area: Box(origin: Vec2(-rect.minX, -rect.minY), size: k.size), rounded: false)
    }

    /// Back, with a pull before and a swing past: `a` and `o` as shares.
    private static func swung(_ u: Double, pull a: Double, past o: Double) -> Double {
        let u = min(max(u, 0), 1)
        let base = ease(u)
        return base - a * sin(.pi * min(u / 0.35, 1)) * (u < 0.35 ? 1 : 0) * 0.5 + o * sin(.pi * max((u - 0.6) / 0.4, 0))
    }

    // MARK: Carousel & Flow

    /// A strip of cards on a curve, running along it, stopping on each.
    private static func strip(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int, vertical: Bool) -> TemplateScene {
        let side = s.f("cardSize") * (vertical ? k.h : k.w) * (vertical ? 1 : 0.8)
        let cell = vertical ? Size2(side * 4 / 3, side) : Size2(side, side * 4 / 3)
        let pitch = (vertical ? cell.height : cell.width) * (1 + s.f("gap"))
        let reach = (vertical ? k.h : k.w) * 1.6
        let copies = max(Int((reach / (Double(n) * pitch)).rounded(.up)), 1)
        let count = n * copies, length = Double(count) * pitch
        let along = turned(p, steps: s.c("motion") == "stop" ? count : nil) * length
        let c = s.f("curve")
        let radius = abs(c) > 0.01 ? (vertical ? k.h : k.w) / (abs(c) * .pi / 2) : 0
        let cards = (0..<count).map { j -> TemplateCard in
            var d = Double(j) * pitch - along
            d = wrap(d / length + 0.5) * length - length / 2
            var at = d, z = 0.0, turn = 0.0
            if radius > 0 {
                let theta = d / radius
                at = radius * sin(theta)
                z = (c > 0 ? -1 : 1) * radius * (1 - cos(theta))
                turn = deg(c > 0 ? theta : -theta)
            }
            let fade = min(max(1 - (abs(d) - reach / 2 + pitch) / pitch, 0), 1)
            if vertical {
                return TemplateCard(j, cell: cell, position: Vec2(k.centre.x, k.centre.y + at), z: z, tilt: Vec2(-turn, 0),
                                    curve: Vec2(0, c > 0 ? radius : -radius), opacity: fade, slot: j % n)
            }
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x + at, k.centre.y), z: z, tilt: Vec2(0, turn),
                                curve: Vec2(c > 0 ? radius : -radius, 0), opacity: fade, slot: j % n)
        }
        return TemplateScene(space: k.camera(0.35), cards: cards)
    }

    /// A great wheel under the frame turning a card at a time onto its top,
    /// pulling back first and swinging past.
    private static func swingWheel(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let width = s.f("cardSize") * k.u * 0.6
        let r = s.f("wheel") * k.u * 0.7
        let hub = Vec2(k.centre.x, k.centre.y + r)
        let (i, f) = step(p, n)
        let moving = 1 - s.f("hold")
        let u = moving > 0 ? min(f / moving, 1) : 1
        let way: Double = s.c("direction") == "back" ? -1 : 1
        let turn = (Double(i) + swung(u, pull: s.f("anticipation"), past: s.f("overshoot"))) * 360 / Double(n) * way
        let cards = (0..<n).map { j -> TemplateCard in
            let a = Double(j) * 360 / Double(n) - turn
            return TemplateCard(j, cell: k.cell(width), position: Vec2(hub.x + r * sin(rad(a)), hub.y - r * cos(rad(a))), rotation: a)
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// The card in the middle square on; those either side turned away
    /// and stacked, as album covers flick past.
    private static func flow(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int, vertical: Bool) -> TemplateScene {
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width * (vertical ? 0.75 : 1))
        let way: Double = s.c("direction") == "back" ? -1 : 1
        let focus = turned(p, steps: s.c("motion") == "stop" ? n : nil) * Double(n) * way
        let side = s.n("sideTilt"), gap = s.f("gap")
        let span = vertical ? cell.height : cell.width
        let cards = (0..<n).map { j -> TemplateCard in
            var d = Double(j) - focus
            d -= (d / Double(n)).rounded() * Double(n)
            let near = min(max(d, -1), 1)
            let out = (abs(d) < 1 ? abs(d) * span * 0.75 : span * 0.75 + (abs(d) - 1) * span * (0.3 + gap)) * (d < 0 ? -1 : 1)
            let z = -abs(near) * span * 0.6
            let fade = min(max(Double(n) / 2 - abs(d) + 0.5, 0), 1)
            if vertical {
                return TemplateCard(j, cell: cell, position: Vec2(k.centre.x, k.centre.y + out), z: z,
                                    tilt: Vec2(near * side, 0), opacity: fade)
            }
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x + out, k.centre.y), z: z,
                                tilt: Vec2(0, -near * side), opacity: fade)
        }
        return TemplateScene(space: k.camera(0.45), cards: cards)
    }

    /// A row stepping a card at a time, the middle one full size, the
    /// others smaller.
    private static func slideCarousel(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let vertical = s.c("axis") == "vertical"
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width)
        let pitch = (vertical ? cell.height : cell.width) * (0.85 + s.f("gap"))
        let focus = turned(p, steps: n) * Double(n)
        let cards = (0..<n).map { j -> TemplateCard in
            var d = Double(j) - focus
            d -= (d / Double(n)).rounded() * Double(n)
            let near = max(1 - abs(d), 0)
            let scale = s.f("sideScale") + (1 - s.f("sideScale")) * near
            let at = d * pitch
            let position = vertical ? Vec2(k.centre.x, k.centre.y + at) : Vec2(k.centre.x + at, k.centre.y)
            return TemplateCard(j, cell: cell, position: position, z: near, scale: scale,
                                opacity: min(max(Double(n) / 2 - abs(d) + 0.5, 0), 1))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Cards overlapping down a diagonal, running along it.
    private static func diagonalRun(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width)
        let pitch = width * (1 - s.f("overlap") * 0.9)
        let copies = max(Int((hypot(k.w, k.h) * 1.4 / (Double(n) * pitch)).rounded(.up)), 1)
        let count = n * copies, length = Double(count) * pitch
        let along = turned(p, steps: s.c("motion") == "step" ? count : nil) * length
        let dir = s.c("direction") == "upRight" ? Vec2(0.8, -0.6) : Vec2(0.8, 0.6)
        let cards = (0..<count).map { j -> TemplateCard in
            let t = wrap(Double(j) / Double(count) - along / length)
            let d = (t - 0.5) * length
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x + d * dir.x, k.centre.y + d * dir.y), z: t, opacity: ends(t), slot: j % n)
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// A row stepping through, the middle card grown, the others stepping
    /// up and down.
    private static func focusSlide(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let vertical = s.c("axis") == "vertical"
        let width = s.f("cardSize") * k.u * 0.7
        let cell = k.cell(width)
        let grow = s.f("centreScale")
        let pitch = (vertical ? cell.height : cell.width) * (1 + s.f("gap"))
        let focus = turned(p, steps: n) * Double(n)
        let cards = (0..<n).map { j -> TemplateCard in
            var d = Double(j) - focus
            d -= (d / Double(n)).rounded() * Double(n)
            let near = max(1 - abs(d), 0)
            let room = (grow - 1) * (vertical ? cell.height : cell.width) / 2
            let at = d * pitch + (d == 0 ? 0 : (d > 0 ? 1 : -1) * room * min(abs(d), 1))
            let zig = (j % 2 == 0 ? 1.0 : -1.0) * s.f("zigzag") * width * (1 - near)
            let position = vertical ? Vec2(k.centre.x + zig, k.centre.y + at) : Vec2(k.centre.x + at, k.centre.y + zig)
            return TemplateCard(j, cell: cell, position: position, z: near, scale: 1 + (grow - 1) * near,
                                opacity: min(max(Double(n) / 2 - abs(d) + 0.5, 0), 1))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Rows of wide and narrow cards, as bricks, running across.
    private static func brickMarquee(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let rows = s.count("rows")
        let gap = s.f("gap") * k.h / Double(rows)
        let h = (k.h - gap * Double(rows + 1)) / Double(rows)
        let patterns: [String: [Double]] = ["one": [1.5, 1, 1.33, 0.75, 1.2], "two": [1, 1.78, 1, 0.75, 1.33, 1],
                                            "three": [0.8, 1.33, 1.78, 0.8, 1.2]]
        let shape = patterns[s.c("layout")] ?? patterns["one"]!
        var cards: [TemplateCard] = []
        var index = 0
        for row in 0..<rows {
            let widths = (0..<shape.count).map { shape[($0 + row * 2) % shape.count] * h }
            let once = widths.reduce(0, +) + gap * Double(widths.count)
            let copies = max(Int((k.w * 1.5 / once).rounded(.up)), 1)
            let length = once * Double(copies)
            let way: Double = (s.c("direction") == "right") != (row % 2 == 1) ? -1 : 1
            let y = gap + h / 2 + Double(row) * (h + gap)
            var x = 0.0
            for c in 0..<copies * widths.count {
                let w = widths[c % widths.count]
                var left = x - way * p * length
                left = wrap(left / length) * length - length / 2 + k.centre.x
                // Exactly its brick, its picture cropped to fill it.
                cards.append(TemplateCard(index, cell: Size2(w, h), position: Vec2(left + w / 2, y), slot: index,
                                          area: Box(origin: .zero, size: Size2(w, h))))
                x += w + gap
                index += 1
            }
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// The card in play fills the frame behind, slowly zooming, while a row
    /// of small cards along the foot lifts it.
    private static func featureReel(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let width = s.f("cardSize") * k.w
        let cell = Size2(width, width * 0.75)
        let pitch = width * 1.12
        let zoom = 1 + s.f("zoom") * f
        var cards: [TemplateCard] = []
        // Behind: the one in play, and the one before fading as it comes.
        let fadeIn = min(f / 0.25, 1)
        for (slot, alpha) in [((i + n - 1) % n, 1 - fadeIn), (i, fadeIn)] where alpha > 0 {
            var hero = piece(cards.count, slot: slot, frameBox(k), k, opacity: alpha * s.f("heroOpacity"))
            hero.scale = slot == i ? zoom : 1 + s.f("zoom")
            cards.append(hero)
        }
        let rowY = k.h - cell.height * 0.8
        for j in 0..<n {
            let x = k.centre.x + (Double(j) - Double(n - 1) / 2) * pitch
            let active = j == i ? ease(min(f / 0.25, 1)) : (j == (i + n - 1) % n ? 1 - ease(min(f / 0.25, 1)) : 0)
            cards.append(TemplateCard(cards.count, cell: cell, position: Vec2(x, rowY - active * s.f("lift") * cell.height),
                                      z: active, scale: 1 + active * 0.08, slot: j))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    // MARK: Grid

    /// The tiles of a grid of `count` (as square as it can be) in the frame.
    private static func grid(_ count: Int, _ k: Kit, gap: Double) -> [Box] {
        let columns = max(Int(Double(count).squareRoot().rounded(.up)), 1)
        let rows = max(Int((Double(count) / Double(columns)).rounded(.up)), 1)
        let g = gap * k.u
        let w = (k.w - g * Double(columns + 1)) / Double(columns), h = (k.h - g * Double(rows + 1)) / Double(rows)
        return (0..<count).map { i in
            let c = i % columns, r = i / columns
            return Box(origin: Vec2(g + Double(c) * (w + g), g + Double(r) * (h + g)), size: Size2(w, h))
        }
    }

    private static func tile(_ index: Int, _ box: Box, slot: Int, scale: Double = 1, opacity: Double = 1, z: Double = 0,
                             tilt: Vec2 = .zero) -> TemplateCard {
        TemplateCard(index, cell: Size2(box.width, box.height), position: box.center, z: z, tilt: tilt, scale: scale,
                     opacity: opacity, slot: slot, area: Box(origin: .zero, size: Size2(box.width, box.height)))
    }

    /// The tiles come in one by one, stay, and go together.
    private static func gridBuild(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let boxes = grid(n, k, gap: s.f("gap"))
        let columns = max(Int(Double(n).squareRoot().rounded(.up)), 1)
        func rank(_ i: Int) -> Double {
            switch s.c("order") {
            case "columns": return Double((i % columns) * 100 + i / columns)
            case "diagonal": return Double((i % columns + i / columns) * 100 + i % columns)
            default: return Double(i)
            }
        }
        let order = (0..<n).sorted { rank($0) < rank($1) }
        let cards = boxes.enumerated().map { i, box -> TemplateCard in
            let turn = Double(order.firstIndex(of: i) ?? i)
            let start = 0.05 + turn / Double(n) * 0.45
            let u = ease((p - start) / 0.12)
            let out = ease((p - 0.88) / 0.1)
            return tile(i, box, slot: i, scale: 0.7 + 0.3 * u, opacity: u * (1 - out))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Each tile in turn comes up close, filling the middle, the others
    /// dimmed behind a veil.
    private static func gridZoom(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let boxes = grid(n, k, gap: s.f("gap"))
        let (i, f) = step(p, n)
        let up = sin(min(f / 0.9, 1) * .pi)
        var cards = boxes.enumerated().filter { $0.offset != i }.map { j, box in tile(j, box, slot: j) }
        cards.append(TemplateCard(n, cell: k.size, position: k.centre, opacity: s.f("dim") * up, color: RGBA(0, 0, 0), rounded: false))
        let box = boxes[i]
        let target = Box(origin: Vec2(k.w * 0.15, k.h * 0.12), size: Size2(k.w * 0.7, k.h * 0.76))
        let mid = Box(minX: box.minX + (target.minX - box.minX) * up, minY: box.minY + (target.minY - box.minY) * up,
                      maxX: box.maxX + (target.maxX - box.maxX) * up, maxY: box.maxY + (target.maxY - box.maxY) * up)
        cards.append(tile(n + 1, mid, slot: i))
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Tiles turning over to the picture on their backs and back again,
    /// one after another.
    private static func flipTiles(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let count = max(n / 2, 1)
        let boxes = grid(count, k, gap: s.f("gap"))
        let across = s.c("axis") == "vertical"
        var cards: [TemplateCard] = []
        for (i, box) in boxes.enumerated() {
            let delay = Double(i) / Double(count) * 0.25
            let over = ease((p - 0.1 - delay) / 0.2) - ease((p - 0.6 - delay) / 0.2)
            let angle = over * 180
            let turn = across ? Vec2(angle, 0) : Vec2(0, angle)
            let back = across ? Vec2(angle + 180, 0) : Vec2(0, angle + 180)
            cards.append(tile(i * 2, box, slot: i, tilt: turn))
            cards.append(tile(i * 2 + 1, box, slot: i + count, tilt: back))
        }
        // Backs turned away are hidden, so each side shows only its face.
        return TemplateScene(space: Space3D(distance: k.u * 3, backOpacity: 0), cards: cards)
    }

    /// Tiles popping up one after another, staying, and going.
    private static func popTiles(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let boxes = grid(n, k, gap: s.f("gap"))
        let shown = s.f("visible")
        let cards = boxes.enumerated().map { i, box -> TemplateCard in
            let start = Double(i) / Double(n) * (1 - shown) * 0.5
            let inn = min(max((p - start) / 0.12, 0), 1)
            let out = min(max((p - start - shown) / 0.1, 0), 1)
            let pop = inn < 1 ? swung(inn, pull: 0, past: 0.15) : 1
            return tile(i, box, slot: i, scale: max(pop * (1 - out), 0.001), opacity: min(inn * 2, 1) * (1 - out))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Rows of cards running across, every other one the other way, turned
    /// across the frame or laid back.
    private static func ticker(_ s: Settings, _ p: Double, _ k: Kit, tilted: Bool) -> TemplateScene {
        let rows = s.count("rows")
        let h = s.f("cardSize") * k.h * 0.9
        let cell = Size2(h * 4 / 3, h)
        let pitch = cell.width * (1 + s.f("gap"))
        let rowPitch = h * (1 + s.f("gap"))
        let span = hypot(k.w, k.h) * 1.3
        let per = max(Int((span / pitch).rounded(.up)) + 1, 2)
        let length = Double(per) * pitch
        let turn = tilted ? 0 : rad(s.n("tilt"))
        var cards: [TemplateCard] = []
        for row in 0..<rows {
            let way: Double = s.c("flow") == "same" || row % 2 == 0 ? 1 : -1
            let y = (Double(row) - Double(rows - 1) / 2) * rowPitch
            for j in 0..<per {
                var x = Double(j) * pitch + Double(row) * pitch * 0.4 - way * p * length
                x = wrap(x / length) * length - length / 2
                let at = Vec2(x * cos(turn) - y * sin(turn), x * sin(turn) + y * cos(turn))
                cards.append(TemplateCard(row * per + j, cell: cell, position: k.centre + at, rotation: deg(turn), slot: row * 5 + j))
            }
        }
        if tilted { return TemplateScene(space: Space3D(distance: k.u * 1.4, orbit: Vec2(s.n("tilt"), 0)), cards: cards) }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Columns drifting up and down, every other one the other way.
    private static func driftColumns(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let columns = s.count("columns")
        let g = s.f("gap") * k.u
        let w = (k.w - g * Double(columns + 1)) / Double(columns)
        let cell = Size2(w, w * 1.25)
        let pitch = cell.height + g
        let per = max(Int((k.h * 1.6 / pitch).rounded(.up)) + 1, 2)
        let length = Double(per) * pitch
        var cards: [TemplateCard] = []
        for c in 0..<columns {
            let way: Double = c % 2 == 0 ? 1 : -1
            let x = g + w / 2 + Double(c) * (w + g)
            for j in 0..<per {
                var y = Double(j) * pitch + Double(c) * pitch * 0.5 - way * p * length
                y = wrap(y / length) * length - length / 2 + k.centre.y
                cards.append(TemplateCard(c * per + j, cell: cell, position: Vec2(x, y), slot: c * 3 + j))
            }
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// One column of cards flicked up a card at a time, as a feed.
    private static func feed(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let width = s.f("cardSize") * k.u
        let cell = Size2(width, width * 0.8)
        let pitch = cell.height * (1 + s.f("gap"))
        let up = turned(p, steps: s.c("motion") == "flick" ? n : nil) * Double(n)
        let cards = (0..<n).map { j -> TemplateCard in
            var d = Double(j) - up
            d -= (d / Double(n)).rounded() * Double(n)
            let y = k.centre.y + d * pitch
            let fade = min(max(1.6 - abs(d) * 0.55, 0), 1)
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x, y), opacity: fade)
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    // MARK: Spotlight & Focus

    /// A card at a time crossing the middle, fading copies following.
    private static func stage(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width * 0.75)
        let travel = s.f("travel") * k.w
        let ghosts = s.count("trail")
        var cards: [TemplateCard] = []
        func place(_ u: Double) -> (Double, Double) {
            // In from the left, a rest in the middle, out to the right.
            if u < 0.3 { let e = ease(u / 0.3); return (-travel * (1 - e), e) }
            if u < 0.7 { return (0, 1) }
            let e = ease((u - 0.7) / 0.3)
            return (travel * e, 1 - e)
        }
        for g in stride(from: ghosts, through: 0, by: -1) {
            let lag = Double(g) * 0.025
            let (x, alpha) = place(max(f - lag, 0))
            cards.append(TemplateCard(cards.count, cell: cell, position: Vec2(k.centre.x + x, k.centre.y),
                                      opacity: alpha * (g == 0 ? 1 : 0.35 / Double(g)), slot: i))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// One picture large, the rest small down a rail beside it; each step
    /// the next takes the large place.
    private static func railFocus(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let g = s.f("gap") * k.u
        let railW = s.f("rail") * k.w
        let main = Box(origin: Vec2(g, g), size: Size2(k.w - railW - g * 3, k.h - g * 2))
        let fade = ease(f / 0.3)
        var cards = [tile(0, main, slot: (i + n - 1) % n), tile(1, main, slot: i, opacity: fade)]
        let h = (k.h - g * Double(n + 1)) / Double(n)
        for j in 0..<n {
            let box = Box(origin: Vec2(k.w - railW - g, g + Double(j) * (h + g)), size: Size2(railW, h))
            let on = j == i ? fade : (j == (i + n - 1) % n ? 1 - fade : 0)
            cards.append(tile(2 + j, box, slot: j, scale: 1 - 0.06 * (1 - on), opacity: 0.45 + 0.55 * on))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// A stack whose top card peels off to the side and goes under.
    private static func peelDeck(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width)
        let peek = s.f("peek") * cell.height
        let cards = (0..<n).map { j -> TemplateCard in
            // Its place in the stack, 0 on top, counting the peel.
            let depth = Double((j - i + n) % n)
            if depth == 0 {
                let e = ease(min(f / 0.6, 1))
                return TemplateCard(j, cell: cell, position: Vec2(k.centre.x + e * width * 1.3, k.centre.y - e * peek * 3),
                                    z: Double(n) - e * Double(n + 1), rotation: e * 18, opacity: 1 - max(e - 0.7, 0) / 0.3)
            }
            let rise = depth - ease(min(f / 0.6, 1))
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x, k.centre.y + rise * peek), z: Double(n) - rise,
                                scale: 1 - rise * 0.04)
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// A picture at a time filling the frame, slowly zooming and drifting,
    /// each fading into the next.
    private static func slowZoom(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        func card(_ index: Int, _ slot: Int, _ u: Double, _ alpha: Double) -> TemplateCard {
            let way: Double
            switch s.c("pan") {
            case "left": way = -1
            case "right": way = 1
            default: way = slot % 2 == 0 ? 1 : -1
            }
            return piece(index, slot: slot, frameBox(k), k, opacity: alpha, scale: 1 + s.f("zoom") * u,
                         offset: Vec2(way * s.f("zoom") * k.w * 0.25 * u, 0))
        }
        let blend = ease((f - 0.85) / 0.15)
        var cards = [card(0, i, f, 1)]
        if blend > 0 { cards.append(card(1, (i + 1) % n, f - 1, blend)) }
        return TemplateScene(space: flat(k), cards: cards)
    }

    // MARK: Reveal & Wipe

    /// The next picture wiped across over this one behind an angled edge,
    /// a glowing line along it: the edge drawn as level strips each
    /// reaching as far as the edge does at its height.
    private static func angledWipe(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let lean = tan(rad(s.n("angle")))
        let sweep = ease(min(f / 0.6, 1))
        let reach = k.w + abs(lean) * k.h
        let front = -abs(lean) * k.h / 2 + sweep * (reach + abs(lean) * k.h / 2)
        var cards = [piece(0, slot: i, frameBox(k), k)]
        let strips = 48
        let h = k.h / Double(strips)
        for r in 0..<strips {
            let y = (Double(r) + 0.5) * h
            let edge = min(max(front + (y - k.h / 2) * lean, 0), k.w)
            guard edge > 0.5 else { continue }
            cards.append(piece(cards.count, slot: (i + 1) % n, Box(origin: Vec2(0, Double(r) * h), size: Size2(edge, h + 0.5)), k))
        }
        if sweep > 0, sweep < 1 {
            let length = k.h / cos(rad(s.n("angle")))
            cards.append(TemplateCard(cards.count, cell: Size2(max(k.u * 0.006, 2), length),
                                      position: Vec2(front, k.h / 2), rotation: -s.n("angle"), opacity: s.f("glow"),
                                      color: RGBA(1, 1, 1), rounded: false))
        }
        // Once across, the next picture is the one behind.
        if sweep >= 1 { cards = [piece(0, slot: (i + 1) % n, frameBox(k), k)] }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// The next picture coming down in upright strips, one after another.
    private static func stripes(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let count = s.count("strips")
        let w = k.w / Double(count)
        var cards = [piece(0, slot: i, frameBox(k), k)]
        for c in 0..<count {
            let start = Double(c) / Double(count) * 0.35
            let u = ease((f - start) / 0.3)
            guard u > 0 else { continue }
            let box = Box(origin: Vec2(Double(c) * w, 0), size: Size2(w + 0.5, k.h))
            // Each strip carries its part of the picture down with it.
            cards.append(piece(cards.count, slot: (i + 1) % n, box, k, offset: Vec2(0, -(1 - u) * k.h)))
        }
        if f > 0.7 { cards = [piece(0, slot: (i + 1) % n, frameBox(k), k)] }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// The next picture in two halves sliding in from either side.
    private static func split(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let at = s.f("ratio") * k.w
        let g = s.f("gap") * k.w
        let u = ease(min(f / 0.55, 1))
        var cards = [piece(0, slot: i, frameBox(k), k)]
        let left = Box(origin: .zero, size: Size2(at - g / 2, k.h))
        let right = Box(origin: Vec2(at + g / 2, 0), size: Size2(k.w - at - g / 2, k.h))
        // Each half carries its part of the picture in with it.
        cards.append(piece(1, slot: (i + 1) % n, left, k, offset: Vec2(0, -(1 - u) * k.h)))
        cards.append(piece(2, slot: (i + 1) % n, right, k, offset: Vec2(0, (1 - u) * k.h)))
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// The next picture coming in as tiles, in order, from the corner,
    /// from the middle, or at random.
    private static func tileWipe(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let rows = s.count("rows"), columns = s.count("columns")
        let w = k.w / Double(columns), h = k.h / Double(rows)
        var cards = [piece(0, slot: i, frameBox(k), k)]
        let total = rows * columns
        for r in 0..<rows {
            for c in 0..<columns {
                let rank: Double
                switch s.c("pattern") {
                case "diagonal": rank = Double(r + c) / Double(rows + columns - 2 == 0 ? 1 : rows + columns - 2)
                case "radial":
                    let dx = Double(c) - Double(columns - 1) / 2, dy = Double(r) - Double(rows - 1) / 2
                    rank = hypot(dx, dy) / max(hypot(Double(columns - 1) / 2, Double(rows - 1) / 2), 1e-9)
                case "random": rank = Double(((r * columns + c) * 7919) % total) / Double(max(total - 1, 1))
                default: rank = Double(r * columns + c) / Double(max(total - 1, 1))
                }
                let u = ease((f - rank * 0.4) / 0.2)
                guard u > 0 else { continue }
                let box = Box(origin: Vec2(Double(c) * w, Double(r) * h), size: Size2(w + 0.5, h + 0.5))
                cards.append(piece(cards.count, slot: (i + 1) % n, box, k, opacity: u, scale: 0.6 + 0.4 * u))
            }
        }
        if f > 0.75 { cards = [piece(0, slot: (i + 1) % n, frameBox(k), k)] }
        return TemplateScene(space: flat(k), cards: cards)
    }

    // MARK: Stack & Scatter

    /// A stack whose top card slides out and goes back under.
    private static func slideStack(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let (i, f) = step(p, n)
        let cell = Size2(s.f("cardSize") * k.w * 0.8, s.f("cardSize") * k.h * 0.8)
        let shrink = s.f("depthScale")
        let cards = (0..<n).map { j -> TemplateCard in
            let depth = Double((j - i + n) % n)
            let e = ease(min(f / 0.55, 1))
            if depth == 0 {
                let out = e < 0.5 ? e * 2 : 1
                return TemplateCard(j, cell: cell, position: Vec2(k.centre.x - out * k.w * 0.9, k.centre.y), z: Double(n),
                                    opacity: 1 - max(out - 0.8, 0) / 0.2)
            }
            let rise = depth - e
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x, k.centre.y - rise * cell.height * 0.04), z: Double(n) - rise,
                                scale: pow(shrink, rise))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Cards dropping one by one onto a pile, askew, the pile clearing as
    /// the loop ends.
    private static func dropStack(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let cell = k.cell(s.f("cardSize") * k.u * 0.6)
        let cards = (0..<n).map { j -> TemplateCard in
            let start = Double(j) / Double(n) * 0.75
            let u = min(max((p - start) / 0.15, 0), 1)
            let fall = 1 - swung(u, pull: 0, past: 0.06)
            let askew = (Double((j * 37) % 11) - 5) / 5 * 12 * s.f("spin")
            let clear = ease((p - 0.9) / 0.1)
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x, k.centre.y - fall * k.h), z: Double(j),
                                rotation: askew * (1 - fall * 0.5), opacity: (u > 0 ? 1 : 0) * (1 - clear))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// A deck fanning out into an overlapping row and gathering again.
    private static func fannedDeck(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let width = s.f("cardSize") * k.u * 0.6
        let cell = k.cell(width)
        let pitch = width * (1 - s.f("overlap"))
        let together = s.c("motion") == "together"
        let cards = (0..<n).map { j -> TemplateCard in
            let delay = together ? 0 : Double(j) / Double(n) * 0.25
            let out = ease((p - 0.05 - delay) / 0.2) - ease((p - 0.6 - delay) / 0.2)
            let x = (Double(j) - Double(n - 1) / 2) * pitch * out
            let fan = (Double(j) - Double(n - 1) / 2) * 4 * out
            return TemplateCard(j, cell: cell, position: Vec2(k.centre.x + x, k.centre.y + abs(fan) * 2), z: Double(j), rotation: fan)
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Cards popping up along a winding path, a trail of the latest ones
    /// fading behind.
    private static func trail(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width)
        let length = s.count("length")
        let total = 48
        let head = p * Double(total)
        var cards: [TemplateCard] = []
        for back in 0..<length {
            let spot = head.rounded(.down) - Double(back)
            let t = wrap(spot / Double(total))
            let at = Vec2(k.centre.x + sin(t * 2 * .pi * 2) * k.w * 0.35, k.centre.y + sin(t * 2 * .pi * 3) * k.h * 0.3)
            let age = head - spot.rounded(.down)
            let pop = min(age / 0.6, 1)
            cards.append(TemplateCard(back, cell: cell, position: at, z: -Double(back), scale: 0.6 + 0.4 * ease(pop),
                                      opacity: max(1 - Double(back) / Double(length), 0), slot: Int(wrap(spot / Double(n)) * Double(n))))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Posters bursting up from the middle to fill the frame and flying
    /// off, one by one or all at once.
    private static func burst(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let volley = s.c("flow") == "volley"
        let cell = k.cell(k.u * 0.5)
        let cards = (0..<n).map { j -> TemplateCard in
            let start = volley ? 0.1 : Double(j) / Double(n)
            let span = volley ? 0.7 : 1 / Double(n)
            let u = min(max((p - start) / span, 0), 1)
            let grow = ease(min(u / 0.4, 1))
            let away = ease((u - 0.7) / 0.3)
            let dir = rad(Double(j) * 360 / Double(n) + 30)
            let out = volley ? Vec2(cos(dir) * k.u * 0.6 * grow, sin(dir) * k.u * 0.6 * grow) : .zero
            return TemplateCard(j, cell: cell, position: k.centre + out, z: Double(j) + grow,
                                rotation: (Double(j % 3) - 1) * 6 * grow, scale: 0.2 + 0.8 * grow + away * 0.4,
                                opacity: (u > 0 ? 1 : 0) * (1 - away))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// Cards thrown up in arcs across the frame, turning as they fly.
    private static func toss(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let cell = k.cell(s.f("cardSize") * k.u)
        let cards = (0..<n).map { j -> TemplateCard in
            let t = wrap(p + Double(j) / Double(n))
            let from = Double((j * 53) % 100) / 100
            let x = k.w * (0.15 + 0.7 * (from * (1 - t) + (1 - from) * t))
            let y = k.h + cell.height - 4 * t * (1 - t) * s.f("height") * (k.h + cell.height)
            return TemplateCard(j, cell: cell, position: Vec2(x, y), z: t, rotation: (t - 0.5) * 2 * s.n("spin"), opacity: ends(t, 0.05))
        }
        return TemplateScene(space: flat(k), cards: cards)
    }

    /// A row of cards changing places, one swap a step.
    private static func shuffle(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let width = s.f("cardSize") * k.u
        let cell = k.cell(width)
        let pitch = width * (1 + s.f("gap"))
        // A cycle of n steps, each moving every card one place on, the end
        // card hopping over the rest back to the start.
        let (i, f) = step(p, n)
        let u = ease(f / 0.6)
        let cards = (0..<n).map { j -> TemplateCard in
            let from = (j + i) % n, to = (j + i + 1) % n
            let hop = to < from
            let x = Double(from) + (Double(to) - Double(from)) * u
            let y = hop ? -sin(u * .pi) * cell.height * 0.9 : 0
            let at = Vec2(k.centre.x + (x - Double(n - 1) / 2) * pitch, k.centre.y + y)
            return TemplateCard(j, cell: cell, position: at, z: hop ? 1 : 0)
        }
        return TemplateScene(space: flat(k), cards: cards)
    }
}
