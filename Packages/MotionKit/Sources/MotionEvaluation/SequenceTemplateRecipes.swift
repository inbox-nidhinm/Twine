import Foundation
import MotionModel

// The sequences (`docs/templates.md`, milestone 7): templates that go
// through several layouts in turn (a ring, a row, a grid, one card up
// close), every card travelling to its place in the next a little after
// the one before, the camera zooming and turning between them. Each is a
// list of `Shot`s played round, the last moving back into the first, so
// the loop has no seam. Every card keeps one cell throughout and changes
// size by its scale, so Split into Layers keeps it.

extension TemplateRecipes {
    static func sequenceSlotCount(_ kind: TemplateKind) -> Int {
        switch kind {
        case .lensRow, .staircase, .diveIn, .parade: 15
        case .threeActs, .unfoldRows, .unfoldColumns: 12
        case .fanWall: 18
        case .zoomStrip: 9
        default: 8
        }
    }

    // MARK: Settings

    private static func size(_ standard: Double, _ name: String = "Card size") -> TemplateControl {
        .number("cardSize", name, standard, 5, 100, .percent, "How big each card is, as a share of the frame.")
    }
    private static let easing = TemplateControl.choice("easing", "Easing",
                                                       [("smooth", "Smooth"), ("natural", "Natural"), ("overshoot", "Overshoot"), ("spring", "Elastic")],
                                                       "How the cards move from one layout to the next.")
    private static let stagger = TemplateControl.number("stagger", "Stagger", 30, 0, 80, .percent,
                                                        "How far behind the one before each card sets off.")
    private static let hold = TemplateControl.number("hold", "Hold", 50, 10, 85, .percent,
                                                     "How long each layout rests before the cards move on.")
    private static let flip = TemplateControl.choice("flip", "Flip", [("across", "Across"), ("down", "Down"), ("none", "None")],
                                                     "Cards turn over as they travel.")
    private static let zoom = TemplateControl.number("zoom", "Camera zoom", 100, 50, 200, .percent, "How close the camera is.")

    static func sequenceControls(_ kind: TemplateKind) -> [TemplateControl] {
        switch kind {
        case .ringBelt:
            [size(26), .number("size", "Ring size", 100, 40, 200, .percent, "How big the ring is."),
             .number("focus", "Focus size", 100, 40, 160, .percent, "How big the card up close is."),
             .number("spread", "Belt spread", 100, 30, 250, .percent, "How far apart the cards in the belt are."), flip, easing, stagger, hold]
        case .lensRow:
            [size(20), .number("lens", "Lens strength", 50, 0, 150, .percent, "How much the cards under the lens grow."),
             .number("focus", "Focus size", 115, 40, 200, .percent, "How big the card in the middle of the orbit is."),
             .number("gap", "Card gap", -20, -60, 60, .percent, "The space between cards in the row; below 0 they overlap."),
             flip, easing, stagger, hold]
        case .staircase:
            [size(15, "Tile size"), .number("gap", "Grid gap", 14, 0, 60, .percent, "The space between tiles in the grid."),
             .number("stair", "Stair gap", 30, 0, 100, .percent, "How far apart the steps are."), zoom, flip, easing, stagger, hold]
        case .diveIn:
            [size(17, "Tile size"), .number("gap", "Gap", 8, 0, 60, .percent, "The space between tiles."), zoom, flip, easing, stagger, hold]
        case .parade:
            [size(30), zoom, flip, easing, stagger, hold]
        case .threeActs:
            [.number("hero", "Hero size", 58, 20, 95, .percent, "How big the card in the first act is."),
             .number("columns", "Columns", 3, 2, 6, .count, "How many columns in the second act."),
             .number("perColumn", "Cards per column", 6, 3, 10, .count, "How many cards each column holds."),
             .number("drift", "Column drift", 22, 0, 100, .percent, "How far the columns drift."),
             .number("rowTilt", "Row tilt", 17, -45, 45, .degrees, "How far the row in the last act leans."),
             .number("rise", "Row rise", 12, 0, 50, .percent, "How steeply the row in the last act climbs."), easing, stagger, hold]
        case .collage:
            [size(30), .number("hero", "Hero size", 52, 20, 95, .percent, "How big the card up close is."), easing, stagger, hold]
        case .fanWall:
            [size(26), .number("deck", "Deck cards", 6, 2, 12, .count, "How many cards the fanned deck shows."),
             .number("fanAngle", "Fan angle", -47, -120, 120, .degrees, "How far the deck fans out."),
             .number("rowShift", "Row shift", 77, 0, 100, .percent, "How far every other row of the wall is shifted."),
             .number("pullBack", "Wall pull-back", 80, 0, 200, .percent, "How far back the wall stands."), easing, stagger, hold]
        case .rowRing:
            [.number("rowSize", "Row card size", 60, 20, 100, .percent, "How big the cards in the row are."),
             .number("gap", "Card gap", 4, -40, 60, .percent, "The space between cards in the row."),
             .number("deckDepth", "Deck depth", 5, 0, 40, .percent, "How far each card in the row stands behind the one before."),
             .number("ringCard", "Ring card size", 30, 10, 80, .percent, "How big the cards on the ring are."),
             .number("size", "Ring size", 36, 15, 80, .percent, "How big the ring is."), easing, stagger, hold]
        case .dial:
            [.number("scatterCard", "Scatter card size", 30, 10, 80, .percent, "How big the scattered cards are."),
             .number("ringCard", "Ring card size", 30, 10, 80, .percent, "How big the cards on the dial are."),
             .number("size", "Ring size", 36, 15, 80, .percent, "How big the dial is."), easing, stagger, hold]
        case .zoomStrip:
            [.number("zoomBy", "Zoom", 2, 1, 4, .plain, "How far the camera zooms in on each strip."),
             .number("gap", "Gap", 2, 0, 20, .percent, "The space between tiles."),
             .choice("axis", "Direction", [("horizontal", "Across"), ("vertical", "Down")], "Whether the strips are rows or columns."),
             easing, hold]
        case .unfoldRows, .unfoldColumns:
            [.number("lines", kind == .unfoldRows ? "Rows" : "Columns", 3, 1, 6, .count,
                     kind == .unfoldRows ? "How many rows the cards spread into." : "How many columns the cards spread into."),
             .number("gap", "Card gap", 3, 0, 40, .percent, "The space between cards."),
             .number("stackSize", "Stack size", 50, 20, 100, .percent, "How big the stacked cards are."), zoom,
             .number("drift", "Drift", 16, 0, 60, .percent, "How far the spread cards drift."),
             .number("lineDelay", kind == .unfoldRows ? "Row delay" : "Column delay", 20, 0, 80, .percent,
                     kind == .unfoldRows ? "How far behind the row before each row sets off." : "How far behind the column before each column sets off."),
             .choice("stack", "Stack at", [("point", "One point"), ("edges", kind == .unfoldRows ? "Row edges" : "Column edges")],
                     "Whether the cards gather in the middle or at the start of their own line."), easing, hold]
        default: []
        }
    }

    // MARK: Scenes

    static func sequenceScene(_ kind: TemplateKind, _ s: Settings, _ p: Double, _ k: Kit, slots: Int) -> TemplateScene {
        let n = min(max(slots, 1), TemplateCards.maxSlots)
        switch kind {
        case .ringBelt: return ringBelt(s, p, k, max(n, 8))
        case .lensRow: return lensRow(s, p, k, max(n, 9))
        case .staircase: return staircase(s, p, k, max(n, 9))
        case .diveIn: return diveIn(s, p, k)
        case .parade: return parade(s, p, k, max(n, 8))
        case .threeActs: return threeActs(s, p, k)
        case .collage: return collage(s, p, k, max(n, 6))
        case .fanWall: return fanWall(s, p, k, max(n, 12))
        case .rowRing: return rowRing(s, p, k, max(n, 6))
        case .dial: return dial(s, p, k, max(n, 6))
        case .zoomStrip: return zoomStrip(s, p, k)
        case .unfoldRows: return unfold(s, p, k, max(n, 6), rows: true)
        case .unfoldColumns: return unfold(s, p, k, max(n, 6), rows: false)
        default: return TemplateScene(space: Space3D(), cards: [])
        }
    }

    // MARK: The engine

    /// A layout at one moment: its cards, the space they are in, and where
    /// the camera looks (`focus`, in the frame's pixels, is brought to the
    /// middle, everything grown `zoom` times about it).
    struct Look {
        var cards: [TemplateCard]
        var space: Space3D
        var focus: Vec2? = nil
        var zoom: Double = 1
    }

    /// One layout of a sequence. `look` gives it at `t`, the share of the
    /// loop since it began; it rests for the hold's share of its `length`,
    /// then its cards move to the next shot's places.
    struct Shot {
        var length: Double = 1
        var look: (Double) -> Look
    }

    /// The cards of a sequence: every one keeps one 4:3 cell `base` wide,
    /// sized by its scale.
    struct Deck {
        let n: Int
        let base: Double
        var mid: Double { Double(n - 1) / 2 }

        func card(_ i: Int, _ at: Vec2, width: Double, z: Double = 0, rotation: Double = 0, tilt: Vec2 = .zero,
                  opacity: Double = 1) -> TemplateCard {
            TemplateCard(i, cell: Size2(base, base * 0.75), position: at, z: z, rotation: rotation, tilt: tilt,
                         scale: base > 0 ? max(width, 0) / base : 1, opacity: opacity)
        }

        /// Card `i`'s rank among `n`, 0 to 1, for setting off in turn.
        func rank(_ i: Int) -> Double { n > 1 ? Double(i) / Double(n - 1) : 0 }
    }

    /// Plays `shots` round at `p`: each rests, then its cards set off for
    /// the next, `rank` saying in what order.
    static func play(_ shots: [Shot], _ p: Double, _ s: Settings, _ k: Kit, lag: Double? = nil, rank: (Int) -> Double) -> TemplateScene {
        let total = shots.reduce(0) { $0 + $1.length }
        guard !shots.isEmpty, total > 0 else { return TemplateScene(space: Space3D(), cards: []) }
        var x = wrap(p) * total
        var i = 0
        while i < shots.count - 1, x >= shots[i].length {
            x -= shots[i].length
            i += 1
        }
        let shot = shots[i]
        let here = shot.look(x / total)
        let rest = shot.length * min(max(s.f("hold"), 0), 0.95)
        guard x > rest else { return seen(here, k) }
        let m = min((x - rest) / (shot.length - rest), 1)
        let next = shots[(i + 1) % shots.count].look(0)
        let lag = min(max(lag ?? s.f("stagger"), 0), 0.9)
        let curve = Easing.preset(EasingPreset(rawValue: s.c("easing")) ?? .smooth, intensity: Easing.standardIntensity)
        let flip = s.c("flip")
        var cards = here.cards
        for c in cards.indices where c < next.cards.count {
            let u = min(max((m - lag * min(max(rank(c), 0), 1)) / (1 - lag), 0), 1)
            var card = mixed(here.cards[c], next.cards[c], curve.progress(u))
            // A whole turn on the way, landing face up.
            if flip == "across" { card.tilt.y += 360 * ease(u) } else if flip == "down" { card.tilt.x += 360 * ease(u) }
            cards[c] = card
        }
        let g = ease(m)
        let middle = k.centre
        let focus = Vec2(lerp(here.focus?.x ?? middle.x, next.focus?.x ?? middle.x, g), lerp(here.focus?.y ?? middle.y, next.focus?.y ?? middle.y, g))
        let zoom = exp(lerp(log(max(here.zoom, 1e-3)), log(max(next.zoom, 1e-3)), g))
        return seen(Look(cards: cards, space: .interpolate(here.space, next.space, g), focus: focus, zoom: zoom), k)
    }

    /// A look through its camera: everything grown about its focus, which
    /// comes to the middle. The camera draws back as much, so the picture
    /// is the same one, larger.
    private static func seen(_ look: Look, _ k: Kit) -> TemplateScene {
        let f = look.focus ?? k.centre, z = look.zoom
        guard z != 1 || f != k.centre else { return TemplateScene(space: look.space, cards: look.cards) }
        var space = look.space
        space.distance *= z
        let cards = look.cards.map { card -> TemplateCard in
            var c = card
            c.position = Vec2(k.centre.x + (card.position.x - f.x) * z, k.centre.y + (card.position.y - f.y) * z)
            c.z *= z
            c.scale *= z
            c.curve = Vec2(card.curve.x * z, card.curve.y * z)
            return c
        }
        return TemplateScene(space: space, cards: cards)
    }

    private static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    private static func mixed(_ a: TemplateCard, _ b: TemplateCard, _ t: Double) -> TemplateCard {
        var c = a
        c.cell = Size2(lerp(a.cell.width, b.cell.width, t), lerp(a.cell.height, b.cell.height, t))
        c.position = Vec2(lerp(a.position.x, b.position.x, t), lerp(a.position.y, b.position.y, t))
        c.z = lerp(a.z, b.z, t)
        c.rotation = lerp(a.rotation, b.rotation, t)
        c.tilt = Vec2(lerp(a.tilt.x, b.tilt.x, t), lerp(a.tilt.y, b.tilt.y, t))
        c.curve = Vec2(lerp(a.curve.x, b.curve.x, t), lerp(a.curve.y, b.curve.y, t))
        c.scale = max(lerp(a.scale, b.scale, t), 0)
        c.opacity = min(max(lerp(a.opacity, b.opacity, t), 0), 1)
        return c
    }

    /// A steady number from 0 to 1 for card `i`, different for each `salt`.
    private static func jitter(_ i: Int, _ salt: Int) -> Double {
        let v = sin(Double(i) * 12.9898 + Double(salt) * 78.233) * 43758.5453
        return v - v.rounded(.down)
    }

    /// An offset along a line of `n` going round, kept within half the
    /// line either side of the middle.
    private static func around(_ o: Double, _ n: Int) -> Double {
        let m = Double(max(n, 1))
        return o - m * (o / m).rounded()
    }

    /// Full strength along a line going round, fading over the last card
    /// at each end, where cards go round to the other.
    private static func lineFade(_ o: Double, _ n: Int) -> Double {
        min(max(Double(n) / 2 - abs(o), 0) / 0.8, 1)
    }

    // MARK: Layouts

    /// A plain space, seen from far off, for flat layouts.
    private static func flatSpace(_ k: Kit) -> Space3D { Space3D(distance: k.u * 4) }

    /// The cards on a circle in the frame's plane, turned `turn` degrees,
    /// upright or (`along`) turned with the circle.
    private static func ring(_ d: Deck, _ k: Kit, radius: Double, width: Double, turn: Double, along: Bool = false) -> [TemplateCard] {
        (0..<d.n).map { i in
            let a = Double(i) * 360 / Double(d.n) + turn
            return d.card(i, Vec2(k.centre.x + radius * sin(rad(a)), k.centre.y - radius * cos(rad(a))), width: width,
                          rotation: along ? a : 0)
        }
    }

    /// One card up close in the middle, the rest gathered behind it out of
    /// sight.
    private static func hero(_ d: Deck, _ k: Kit, _ h: Int, width: Double) -> [TemplateCard] {
        (0..<d.n).map { i in
            i == h % d.n ? d.card(i, k.centre, width: width, z: 2)
                : d.card(i, k.centre, width: width * 0.8, z: -2 - Double(i), opacity: 0)
        }
    }

    /// A row across the frame at `y`, cards `pitch` apart, card `n / 2`
    /// in the middle, moved on `scroll` places and going round; `grow`
    /// sizes each by its offset from the middle, in places.
    private static func row(_ d: Deck, _ k: Kit, y: Double, width: Double, pitch: Double, scroll: Double,
                            grow: (Double) -> Double = { _ in 1 }) -> [TemplateCard] {
        (0..<d.n).map { i in
            let o = around(Double(i - d.n / 2) + scroll, d.n)
            let g = grow(o)
            return d.card(i, Vec2(k.centre.x + o * pitch, y), width: width * g, z: (g - 1) * width * 0.3, opacity: lineFade(o, d.n))
        }
    }

    /// The cards in a grid of `columns`, `width` wide and `gap` apart
    /// (pixels), centred on `centre`; cards past the grid wait unseen in
    /// its middle.
    private static func grid(_ d: Deck, _ k: Kit, columns: Int, rows: Int, width: Double, gap: Double, centre: Vec2? = nil,
                             shift: Vec2 = .zero) -> [TemplateCard] {
        let c0 = centre ?? k.centre
        let w = width + gap, h = width * 0.75 + gap
        return (0..<d.n).map { i in
            let r = i / max(columns, 1), c = i % max(columns, 1)
            guard r < rows else { return d.card(i, c0, width: width * 0.6, z: -4, opacity: 0) }
            let x = c0.x + (Double(c) - Double(columns - 1) / 2) * w + shift.x
            let y = c0.y + (Double(r) - Double(rows - 1) / 2) * h + shift.y
            return d.card(i, Vec2(x, y), width: width)
        }
    }

    /// Where card `i` sits in a grid of `columns`, as `grid` puts it.
    private static func cellCentre(_ i: Int, columns: Int, rows: Int, width: Double, gap: Double, _ k: Kit) -> Vec2 {
        let r = i / max(columns, 1), c = i % max(columns, 1)
        return Vec2(k.centre.x + (Double(c) - Double(columns - 1) / 2) * (width + gap),
                    k.centre.y + (Double(r) - Double(rows - 1) / 2) * (width * 0.75 + gap))
    }

    /// The cards strewn over the frame, askew, drifting a little with `t`.
    private static func scatter(_ d: Deck, _ k: Kit, width: Double, spread: Double, t: Double, salt: Int = 0) -> [TemplateCard] {
        (0..<d.n).map { i in
            let x = (jitter(i, 1 + salt) - 0.5) * spread * k.w, y = (jitter(i, 2 + salt) - 0.5) * spread * k.h
            let drift = sin(2 * .pi * (t + jitter(i, 4))) * k.u * 0.015
            return d.card(i, Vec2(k.centre.x + x + drift, k.centre.y + y - drift), width: width * (0.85 + 0.3 * jitter(i, 5)),
                          z: Double(i) * 0.1, rotation: (jitter(i, 3 + salt) - 0.5) * 24)
        }
    }

    /// The cards in a neat pile at `at`, each a touch askew.
    private static func pile(_ d: Deck, at: Vec2, width: Double) -> [TemplateCard] {
        (0..<d.n).map { i in
            d.card(i, Vec2(at.x + (jitter(i, 7) - 0.5) * width * 0.04, at.y + (jitter(i, 8) - 0.5) * width * 0.04), width: width,
                   z: Double(i) * 0.1, rotation: (jitter(i, 9) - 0.5) * 6)
        }
    }

    // MARK: The sequences

    /// A ring, one card up close, a belt across the frame, another card.
    private static func ringBelt(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("cardSize") * k.u)
        let space = Space3D(distance: k.u * 2.5)
        let close = s.f("focus") * k.u * 0.62
        let ringShot = Shot { t in Look(cards: ring(d, k, radius: s.f("size") * k.u * 0.32, width: d.base, turn: t * 90), space: space) }
        let belt = Shot { t in
            let length = (k.w * k.w + k.h * k.h).squareRoot()
            let way = length > 0 ? Vec2(k.w / length, k.h / length) : Vec2(1, 0)
            let pitch = d.base * s.f("spread") * 0.42
            let cards = (0..<n).map { i -> TemplateCard in
                let o = around(Double(i) - d.mid + t * 3, n)
                let near = max(1 - abs(o) / 3, 0)
                return d.card(i, Vec2(k.centre.x + way.x * o * pitch, k.centre.y + way.y * o * pitch), width: d.base * (1 + 0.4 * near),
                              z: near * d.base * 0.3, opacity: lineFade(o, n))
            }
            return Look(cards: cards, space: space)
        }
        return play([ringShot, Shot { _ in Look(cards: hero(d, k, 0, width: close), space: space) },
                     belt, Shot { _ in Look(cards: hero(d, k, n / 2, width: close), space: space) }], p, s, k, rank: d.rank)
    }

    /// A row under a lens, a grid with the lens going round it, then the
    /// cards circling one in the middle.
    private static func lensRow(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("cardSize") * k.u)
        let space = flatSpace(k)
        let lens = s.f("lens")
        func swell(_ distance: Double) -> Double { 1 + lens * 1.2 * exp(-distance * distance / 1.2) }
        let rowShot = Shot { t in
            Look(cards: row(d, k, y: k.centre.y, width: d.base, pitch: d.base * (1 + s.f("gap")), scroll: -t * 4, grow: { swell($0) }),
                 space: space)
        }
        let columns = max(Int((Double(n) * 1.6).squareRoot().rounded()), 1), rows = (n + columns - 1) / columns
        let gridShot = Shot { t in
            let width = min(k.w * 0.82 / Double(columns), k.h * 0.82 / Double(rows) / 0.75) * 0.85
            let gap = width * 0.15
            let a = 2 * .pi * t * 2
            let spot = Vec2(k.centre.x + sin(a) * k.w * 0.25, k.centre.y - cos(a) * k.h * 0.18)
            var cards = grid(d, k, columns: columns, rows: rows, width: width, gap: gap)
            for i in cards.indices where cards[i].opacity > 0 {
                let dx = (cards[i].position.x - spot.x) / (width + gap), dy = (cards[i].position.y - spot.y) / (width * 0.75 + gap)
                let g = swell((dx * dx + dy * dy).squareRoot())
                cards[i].scale *= g
                cards[i].z = (g - 1) * width * 0.3
            }
            return Look(cards: cards, space: space)
        }
        let orbitShot = Shot { t in
            let h = n / 2
            let cards = (0..<n).map { i -> TemplateCard in
                if i == h { return d.card(i, k.centre, width: d.base * s.f("focus") * 1.6, z: 4) }
                let j = i < h ? i : i - 1
                let a = rad(Double(j) * 360 / Double(n - 1) + t * 60)
                return d.card(i, Vec2(k.centre.x + sin(a) * k.w * 0.36, k.centre.y - cos(a) * k.h * 0.34), width: d.base * 0.8)
            }
            return Look(cards: cards, space: space)
        }
        return play([rowShot, gridShot, orbitShot], p, s, k, rank: d.rank)
    }

    /// A grid, a staircase of cards in depth, the grid again and the camera
    /// going up close to one tile.
    private static func staircase(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let columns = max(Int((Double(n) * 1.7).squareRoot().rounded()), 1), rows = (n + columns - 1) / columns
        // As set, but never past the frame.
        let fit = min(k.w * 0.92 / (Double(columns) * (1 + s.f("gap"))), k.h * 0.9 / (Double(rows) * (0.75 + s.f("gap"))))
        let width = min(s.f("cardSize") * k.w, fit) * s.f("zoom")
        let d = Deck(n: n, base: width)
        let gap = width * s.f("gap")
        let flat = k.camera(0.5, backs: 0)
        let gridShot = Shot { _ in Look(cards: grid(d, k, columns: columns, rows: rows, width: width, gap: gap), space: flat) }
        let stairs = Shot { t in
            let step = width * (0.5 + s.f("stair"))
            let cards = (0..<n).map { i -> TemplateCard in
                let o = around(Double(i - n / 2) - t * 2, n)
                return d.card(i, Vec2(k.centre.x + o * step * 0.7, k.centre.y - o * step * 0.16 + width * 1.2), width: width * 1.2,
                              z: -o * step * 0.4, tilt: Vec2(40, 0), opacity: lineFade(o, n))
            }
            var space = flat
            space.orbit = Vec2(10, -25)
            return Look(cards: cards, space: space)
        }
        let target = min(n - 1, columns * (rows / 2) + columns / 2)
        let close = Shot { _ in
            Look(cards: grid(d, k, columns: columns, rows: rows, width: width, gap: gap), space: flat,
                 focus: cellCentre(target, columns: columns, rows: rows, width: width, gap: gap, k), zoom: k.w * 0.6 / max(width, 1))
        }
        return play([gridShot, stairs, gridShot, close], p, s, k, rank: d.rank)
    }

    /// A wall of tiles seen at an angle; the camera dives into one until
    /// it fills the frame, pulls out to the wall turned the other way, and
    /// dives into another.
    private static func diveIn(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let columns = 6, rows = 4, n = columns * rows
        // Wide enough that the wall fills the frame either way up.
        let width = s.f("cardSize") * max(k.w, k.h * 1.6) * 1.2 * s.f("zoom")
        let d = Deck(n: n, base: width)
        let gap = width * s.f("gap")
        func wall(_ turn: Double) -> Shot {
            Shot { t in
                var space = k.camera(0.5)
                space.orbit = Vec2(18, turn)
                return Look(cards: grid(d, k, columns: columns, rows: rows, width: width, gap: gap, shift: Vec2(t * width * 0.3, 0)),
                            space: space)
            }
        }
        func dive(_ i: Int) -> Shot {
            Shot { _ in
                Look(cards: grid(d, k, columns: columns, rows: rows, width: width, gap: gap), space: k.camera(0.5),
                     focus: cellCentre(i, columns: columns, rows: rows, width: width, gap: gap, k),
                     zoom: min(k.w / max(width, 1), k.h / max(width * 0.75, 1)) * 0.9)
            }
        }
        // The tiles set off corner to corner.
        return play([wall(-16), dive(8), wall(16), dive(15)], p, s, k, rank: { i in
            Double(i / columns + i % columns) / Double(rows + columns - 2)
        })
    }

    /// One card up close, the cards popping up in a row that parades
    /// across, a loose pile, another card.
    private static func parade(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("cardSize") * k.u * s.f("zoom"))
        let space = flatSpace(k)
        let close = min(k.w, k.h * 4 / 3) * 0.62 * s.f("zoom")
        let rowShot = Shot { t in
            var cards = row(d, k, y: k.centre.y, width: d.base, pitch: d.base * 1.12, scroll: -t * 5)
            for i in cards.indices { cards[i].position.y += sin(2 * .pi * (t * 3 + Double(i) * 0.17)) * k.u * 0.025 }
            return Look(cards: cards, space: space)
        }
        let pileShot = Shot { t in Look(cards: scatter(d, k, width: d.base * 0.9, spread: 0.32, t: t), space: space) }
        return play([Shot { _ in Look(cards: hero(d, k, 0, width: close), space: space) }, rowShot, pileShot,
                     Shot { _ in Look(cards: hero(d, k, n / 2, width: close), space: space) }], p, s, k, rank: d.rank)
    }

    /// Three acts: big cards sliding by one at a time, columns drifting
    /// against each other, and a leaning row climbing across.
    private static func threeActs(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let columns = s.count("columns"), per = s.count("perColumn"), n = columns * per
        let big = s.f("hero") * k.w
        let d = Deck(n: n, base: big)
        let space = flatSpace(k)
        let heroShot = Shot { t in
            let step = turned(min(t * 3 / max(s.f("hold"), 0.1), 1), steps: 3) * 3
            return Look(cards: row(d, k, y: k.centre.y, width: big, pitch: big + k.w * 0.3, scroll: -step), space: space)
        }
        let colWidth = k.w * 0.86 / Double(columns)
        let columnsShot = Shot { t in
            let width = colWidth * 0.9, pitch = width * 0.75 + colWidth * 0.1
            let cards = (0..<n).map { i -> TemplateCard in
                let c = i / per, j = i % per
                let way: Double = c % 2 == 0 ? 1 : -1
                let o = around(Double(j) - Double(per - 1) / 2 + way * t * s.f("drift") * 8, per)
                return d.card(i, Vec2(k.centre.x + (Double(c) - Double(columns - 1) / 2) * colWidth, k.centre.y + o * pitch),
                              width: width, opacity: lineFade(o, per))
            }
            return Look(cards: cards, space: space)
        }
        let climb = Shot { t in
            let width = k.w * 0.22, pitch = width * 1.08
            let rise = s.f("rise") * 2.5
            let cards = (0..<n).map { i -> TemplateCard in
                let o = around(Double(i) - d.mid - t * 4, n)
                return d.card(i, Vec2(k.centre.x + o * pitch, k.centre.y - o * pitch * rise), width: width,
                              rotation: -s.n("rowTilt"), opacity: lineFade(o, n))
            }
            return Look(cards: cards, space: space)
        }
        return play([heroShot, columnsShot, climb], p, s, k, rank: d.rank)
    }

    /// A collage, one card up close, a reel running across, another card.
    private static func collage(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("cardSize") * k.u)
        let space = flatSpace(k)
        let close = s.f("hero") * k.w
        let collageShot = Shot { t in
            let cards = (0..<n).map { i -> TemplateCard in
                let o = Double(i) - d.mid
                let along = o / max(d.mid, 1)
                let drift = sin(2 * .pi * (t + jitter(i, 4))) * k.u * 0.012
                return d.card(i, Vec2(k.centre.x + along * k.w * 0.32 + (jitter(i, 1) - 0.5) * k.w * 0.12 + drift,
                                      k.centre.y + along * k.h * 0.22 + (jitter(i, 2) - 0.5) * k.h * 0.3),
                              width: d.base * (0.8 + 0.4 * jitter(i, 5)), z: jitter(i, 6), rotation: (jitter(i, 3) - 0.5) * 16)
            }
            return Look(cards: cards, space: space)
        }
        let reel = Shot { t in Look(cards: row(d, k, y: k.centre.y, width: d.base * 1.1, pitch: d.base * 1.2, scroll: -t * 4), space: space) }
        return play([collageShot, Shot { _ in Look(cards: hero(d, k, 0, width: close), space: space) }, reel,
                     Shot { _ in Look(cards: hero(d, k, n / 2, width: close), space: space) }], p, s, k, rank: d.rank)
    }

    /// A deck, fanned out, then dealt into a wall of shifted rows standing
    /// back in depth.
    private static func fanWall(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("cardSize") * k.u * 1.4)
        let deck = min(s.count("deck"), n)
        let space = k.camera(0.45)
        // The deck's own cards are the last, so they lie on top.
        func inDeck(_ i: Int) -> Int? { i >= n - deck ? i - (n - deck) : nil }
        let pileShot = Shot { _ in
            let cards = (0..<n).map { i -> TemplateCard in
                let j = Double(inDeck(i) ?? 0)
                return d.card(i, Vec2(k.centre.x + j * d.base * 0.02, k.centre.y - j * d.base * 0.02), width: d.base,
                              z: Double(i) * 0.1, opacity: inDeck(i) == nil ? 0 : 1)
            }
            return Look(cards: cards, space: space)
        }
        let fan = Shot { t in
            let angle = s.n("fanAngle")
            let pivot = Vec2(k.centre.x, k.centre.y + d.base * 0.9)
            let cards = (0..<n).map { i -> TemplateCard in
                guard let j = inDeck(i) else { return d.card(i, k.centre, width: d.base, z: -1, opacity: 0) }
                let a = (deck > 1 ? Double(j) / Double(deck - 1) - 0.5 : 0) * angle + sin(2 * .pi * t) * 3
                let r = d.base * 0.9
                return d.card(i, Vec2(pivot.x + r * sin(rad(a)), pivot.y - r * cos(rad(a))), width: d.base, z: Double(j) * 0.1, rotation: a)
            }
            return Look(cards: cards, space: space)
        }
        let perRow = max((n + 2) / 3, 1)
        let wallShot = Shot { t in
            let width = d.base * 0.9, pitch = width * 1.08
            let cards = (0..<n).map { i -> TemplateCard in
                let r = i / perRow, j = i % perRow
                let shift = r % 2 == 1 ? s.f("rowShift") * 0.5 : 0
                let o = around(Double(j) - Double(perRow - 1) / 2 + shift + t * 1.5, perRow)
                return d.card(i, Vec2(k.centre.x + o * pitch, k.centre.y + (Double(r) - 1) * width * 0.83), width: width,
                              z: -s.f("pullBack") * k.u * 0.5, opacity: lineFade(o, perRow))
            }
            var turned = space
            turned.orbit = Vec2(8, -20)
            return Look(cards: cards, space: turned)
        }
        return play([pileShot, fan, wallShot], p, s, k, rank: { 1 - d.rank($0) })
    }

    /// A row standing back in depth, one card up close, then a ring that
    /// turns.
    private static func rowRing(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("rowSize") * k.u * 0.6)
        let space = k.camera(0.35)
        let rowShot = Shot { t in
            var cards = row(d, k, y: k.centre.y, width: d.base, pitch: d.base * (1 + s.f("gap")), scroll: -t * 3)
            for i in cards.indices { cards[i].z = -abs(cards[i].position.x - k.centre.x) / max(d.base, 1) * s.f("deckDepth") * k.u }
            return Look(cards: cards, space: space)
        }
        let ringShot = Shot { t in
            Look(cards: ring(d, k, radius: s.f("size") * k.u, width: s.f("ringCard") * k.u * 0.6, turn: t * 90), space: space)
        }
        return play([rowShot, Shot { _ in Look(cards: hero(d, k, 0, width: k.u * 0.6), space: space) }, ringShot], p, s, k, rank: d.rank)
    }

    /// Cards strewn about, gathered onto a dial that ticks round, then one
    /// card up close.
    private static func dial(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int) -> TemplateScene {
        let d = Deck(n: n, base: s.f("scatterCard") * k.u * 0.7)
        let space = flatSpace(k)
        let scatterShot = Shot { t in Look(cards: scatter(d, k, width: d.base, spread: 0.7, t: t), space: space) }
        let dialShot = Shot { t in
            let ticks = turned(min(t * 3 / max(s.f("hold"), 0.1), 1), steps: 3) * 3 * 360 / Double(n)
            return Look(cards: ring(d, k, radius: s.f("size") * k.u, width: s.f("ringCard") * k.u * 0.7, turn: ticks), space: space)
        }
        return play([scatterShot, dialShot, Shot { _ in Look(cards: hero(d, k, 0, width: k.u * 0.6), space: space) }], p, s, k, rank: d.rank)
    }

    /// A grid seen strip by strip, the camera close in and gliding along
    /// each row (or column), then the whole grid.
    private static func zoomStrip(_ s: Settings, _ p: Double, _ k: Kit) -> TemplateScene {
        let columns = 3, rows = 3, n = 9
        let gap = s.f("gap") * k.w
        let width = min((k.w - gap * 4) / 3, ((k.h - gap * 4) / 3 - 0) / 0.75)
        let d = Deck(n: n, base: width)
        let space = flatSpace(k)
        let cards = grid(d, k, columns: columns, rows: rows, width: width, gap: gap)
        let down = s.c("axis") == "vertical"
        let z = s.n("zoomBy")
        func strip(_ line: Int) -> Shot {
            Shot { t in
                let a = cellCentre(down ? line : line * columns, columns: columns, rows: rows, width: width, gap: gap, k)
                let b = cellCentre(down ? line + columns * (rows - 1) : line * columns + columns - 1, columns: columns, rows: rows,
                                   width: width, gap: gap, k)
                // Glides from a third of the way along to two thirds, and
                // on into the next while the cards move.
                let u = 0.25 + min(t * 4 / max(s.f("hold"), 0.1), 1) * 0.5
                return Look(cards: cards, space: space, focus: Vec2(lerp(a.x, b.x, u), lerp(a.y, b.y, u)), zoom: z)
            }
        }
        return play([strip(0), strip(1), strip(2), Shot { _ in Look(cards: cards, space: space) }], p, s, k, rank: { _ in 0 })
    }

    /// The cards gathered in a stack spread out into rows (or columns)
    /// that drift, then gather again.
    private static func unfold(_ s: Settings, _ p: Double, _ k: Kit, _ n: Int, rows: Bool) -> TemplateScene {
        let lines = min(s.count("lines"), n), per = (n + lines - 1) / lines
        let long = rows ? k.w : k.h, across = rows ? k.h : k.w
        let gap = s.f("gap")
        // Each card's width, so a line runs a little past the frame and
        // the lines fill it across.
        let width = min(long * 1.15 / (Double(per) * (1 + gap)), across * 0.9 / Double(lines) / (rows ? 0.75 + gap : 1 + gap))
        let d = Deck(n: n, base: width)
        let space = flatSpace(k)
        let along = rows ? width * (1 + gap) : width * (0.75 + gap)
        let apart = rows ? width * (0.75 + gap) : width * (1 + gap)
        func place(_ line: Int, _ o: Double) -> Vec2 {
            let a = (Double(line) - Double(lines - 1) / 2) * apart
            return rows ? Vec2(k.centre.x + o * along, k.centre.y + a) : Vec2(k.centre.x + a, k.centre.y + o * along)
        }
        let stack = Shot(length: 0.8) { _ in
            let cards = (0..<n).map { i -> TemplateCard in
                let line = i / per, j = i % per
                let at = s.c("stack") == "edges" ? place(line, -Double(per - 1) / 2) : k.centre
                return d.card(i, Vec2(at.x + Double(j) * width * 0.015, at.y - Double(j) * width * 0.015),
                              width: width * s.f("stackSize") * 2, z: Double(j) * 0.1,
                              rotation: (jitter(i, 9) - 0.5) * 8)
            }
            return Look(cards: cards, space: space, zoom: s.f("zoom"))
        }
        let spread = Shot(length: 1.4) { t in
            let cards = (0..<n).map { i -> TemplateCard in
                let line = i / per, j = i % per
                let way: Double = line % 2 == 0 ? 1 : -1
                let o = Double(j) - Double(per - 1) / 2 + way * sin(.pi * t) * s.f("drift") * 3
                return d.card(i, place(line, o), width: width)
            }
            return Look(cards: cards, space: space, zoom: s.f("zoom"))
        }
        let delay = s.f("lineDelay")
        return play([stack, spread], p, s, k, lag: min(0.15 + delay, 0.8), rank: { i in
            let line = Double(i / per), j = Double(i % per)
            return min((line * delay + j / Double(max(per, 1)) * 0.3) / max(Double(lines - 1) * delay + 0.3, 0.01), 1)
        })
    }
}
