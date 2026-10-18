import Foundation
import MotionModel
import MotionEvaluation

/// The headed groups the template picker shows, in order.
public enum TemplateGroup: String, Sendable, CaseIterable {
    case perspective, sequence, isometric, orbit, flow, grid, spotlight, reveal, stack

    public var title: String {
        switch self {
        case .perspective: "3D & Perspective"
        case .sequence: "Sequences"
        case .isometric: "Isometric"
        case .orbit: "Orbit"
        case .flow: "Carousel & Flow"
        case .grid: "Grid"
        case .spotlight: "Spotlight & Focus"
        case .reveal: "Reveal & Wipe"
        case .stack: "Stack & Scatter"
        }
    }
}

/// A template as the picker lists it.
public struct TemplateInfo: Sendable, Equatable, Identifiable {
    public let kind: TemplateKind
    public let name: String
    public let group: TemplateGroup

    public var id: String { kind.rawValue }
}

/// Adding templates, and turning one into ordinary layers.
public enum Templates {
    /// In the order the picker shows them, group by group.
    public static let library: [TemplateInfo] = [
        TemplateInfo(kind: .ringStream, name: "Ring Stream", group: .perspective),
        TemplateInfo(kind: .curvedWall, name: "Curved Wall", group: .perspective),
        TemplateInfo(kind: .globe, name: "Globe", group: .perspective),
        TemplateInfo(kind: .tiltedGlobe, name: "Tilted Globe", group: .perspective),
        TemplateInfo(kind: .curvedCascade, name: "Curved Cascade", group: .perspective),
        TemplateInfo(kind: .columnWall, name: "Column Wall", group: .perspective),
        TemplateInfo(kind: .parallaxColumns, name: "Parallax Columns", group: .perspective),
        TemplateInfo(kind: .tunnel, name: "Tunnel", group: .perspective),
        TemplateInfo(kind: .spiral, name: "Spiral", group: .perspective),
        TemplateInfo(kind: .depthStack, name: "Depth Stack", group: .perspective),
        TemplateInfo(kind: .carouselRing, name: "Carousel Ring", group: .perspective),
        TemplateInfo(kind: .verticalRing, name: "Vertical Ring", group: .perspective),
        TemplateInfo(kind: .ringBelt, name: "Ring to Belt", group: .sequence),
        TemplateInfo(kind: .lensRow, name: "Lens Row", group: .sequence),
        TemplateInfo(kind: .staircase, name: "Staircase", group: .sequence),
        TemplateInfo(kind: .diveIn, name: "Dive In", group: .sequence),
        TemplateInfo(kind: .parade, name: "Parade", group: .sequence),
        TemplateInfo(kind: .threeActs, name: "Three Acts", group: .sequence),
        TemplateInfo(kind: .collage, name: "Collage", group: .sequence),
        TemplateInfo(kind: .fanWall, name: "Fan to Wall", group: .sequence),
        TemplateInfo(kind: .rowRing, name: "Row to Ring", group: .sequence),
        TemplateInfo(kind: .dial, name: "Dial", group: .sequence),
        TemplateInfo(kind: .zoomStrip, name: "Zoom Strip", group: .sequence),
        TemplateInfo(kind: .unfoldRows, name: "Unfold Rows", group: .sequence),
        TemplateInfo(kind: .unfoldColumns, name: "Unfold Columns", group: .sequence),
        TemplateInfo(kind: .isoStream, name: "Iso Stream", group: .isometric),
        TemplateInfo(kind: .isoSpotlight, name: "Iso Spotlight", group: .isometric),
        TemplateInfo(kind: .isoSwing, name: "Iso Swing", group: .isometric),
        TemplateInfo(kind: .orbit, name: "Orbit", group: .orbit),
        TemplateInfo(kind: .halo, name: "Halo", group: .orbit),
        TemplateInfo(kind: .quadOrbit, name: "Quad Orbit", group: .orbit),
        TemplateInfo(kind: .photoLoop, name: "Photo Loop", group: .orbit),
        TemplateInfo(kind: .zoomOrbit, name: "Zoom Orbit", group: .orbit),
        TemplateInfo(kind: .vortex, name: "Vortex", group: .orbit),
        TemplateInfo(kind: .wheel, name: "Wheel", group: .orbit),
        TemplateInfo(kind: .halfWheel, name: "Half Wheel", group: .orbit),
        TemplateInfo(kind: .curvedColumn, name: "Curved Column", group: .flow),
        TemplateInfo(kind: .filmRoll, name: "Film Roll", group: .flow),
        TemplateInfo(kind: .swingWheel, name: "Swing Wheel", group: .flow),
        TemplateInfo(kind: .flow, name: "Flow", group: .flow),
        TemplateInfo(kind: .verticalFlow, name: "Vertical Flow", group: .flow),
        TemplateInfo(kind: .slideCarousel, name: "Slide Carousel", group: .flow),
        TemplateInfo(kind: .diagonalRun, name: "Diagonal Run", group: .flow),
        TemplateInfo(kind: .focusSlide, name: "Focus Slide", group: .flow),
        TemplateInfo(kind: .brickMarquee, name: "Brick Marquee", group: .flow),
        TemplateInfo(kind: .featureReel, name: "Feature Reel", group: .flow),
        TemplateInfo(kind: .gridBuild, name: "Grid Build", group: .grid),
        TemplateInfo(kind: .gridZoom, name: "Grid Zoom", group: .grid),
        TemplateInfo(kind: .flipTiles, name: "Flip Tiles", group: .grid),
        TemplateInfo(kind: .popTiles, name: "Pop Tiles", group: .grid),
        TemplateInfo(kind: .ticker, name: "Ticker", group: .grid),
        TemplateInfo(kind: .tiltedTicker, name: "Tilted Ticker", group: .grid),
        TemplateInfo(kind: .driftColumns, name: "Drift Columns", group: .grid),
        TemplateInfo(kind: .feed, name: "Feed", group: .grid),
        TemplateInfo(kind: .stage, name: "Stage", group: .spotlight),
        TemplateInfo(kind: .railFocus, name: "Rail Focus", group: .spotlight),
        TemplateInfo(kind: .peelDeck, name: "Peel Deck", group: .spotlight),
        TemplateInfo(kind: .slowZoom, name: "Slow Zoom", group: .spotlight),
        TemplateInfo(kind: .angledWipe, name: "Angled Wipe", group: .reveal),
        TemplateInfo(kind: .stripes, name: "Stripes", group: .reveal),
        TemplateInfo(kind: .split, name: "Split", group: .reveal),
        TemplateInfo(kind: .tileWipe, name: "Tile Wipe", group: .reveal),
        TemplateInfo(kind: .slideStack, name: "Slide Stack", group: .stack),
        TemplateInfo(kind: .dropStack, name: "Drop Stack", group: .stack),
        TemplateInfo(kind: .fannedDeck, name: "Fanned Deck", group: .stack),
        TemplateInfo(kind: .trail, name: "Trail", group: .stack),
        TemplateInfo(kind: .burst, name: "Burst", group: .stack),
        TemplateInfo(kind: .toss, name: "Toss", group: .stack),
        TemplateInfo(kind: .shuffle, name: "Shuffle", group: .stack),
    ]

    public static func name(of kind: TemplateKind) -> String {
        library.first { $0.kind == kind }?.name ?? kind.rawValue
    }

    /// The pictures in `layers`, in order, for a template's slots: each
    /// layer's picture fill.
    public static func pictures(in layers: [Layer]) -> [UUID] {
        layers.compactMap { $0.picture?.paint.mediaID }
    }

    /// A new template frame of `kind` filling `composition`, its slots the
    /// pictures given and empty ones after, as many as the template has, or
    /// more when more pictures are given. It clips, with no fill of its own.
    public static func frame(_ kind: TemplateKind, filling composition: Composition, pictures: [UUID] = []) -> Layer {
        let count = max(TemplateRecipes.slotCount(kind), pictures.count)
        let slots: [UUID?] = pictures + Array(repeating: nil, count: count - pictures.count)
        let size = Size2(Double(composition.width), Double(composition.height))
        return Layer(name: name(of: kind), content: .group(GroupContent(clipsContent: true, frame: FrameStyle(),
                                                                       template: TemplateSetup(kind: kind, slots: slots,
                                                                                               pose: TemplateRecipes.restingPose(kind)))),
                     size: size, position: Vec2(size.width / 2, size.height / 2))
    }

    /// Adding a template of `kind` to `project` in front of everything, as
    /// one undo step: its frame, its bar from the start of the scene to its
    /// end, and in place of `replacing`, the picture layers whose pictures
    /// went into its slots (as Use as Mask takes the layers it is given).
    public static func adding(_ kind: TemplateKind, to project: Project, replacing: [Layer] = []) -> (command: EditorCommand, frameID: UUID) {
        let frame = frame(kind, filling: project.composition, pictures: pictures(in: replacing))
        let bar = Action(target: frame.id, start: 0, duration: max(project.composition.duration, 0.1), easing: .linear,
                         name: name(of: kind), rowOrder: ActionFactory.nextRowOrder(in: project), spec: .template(TemplatePlay()))
        var commands: [EditorCommand] = [.insertLayers([frame], parentID: nil, index: nil), .insertActions([bar])]
        let taken = Set(replacing.filter { $0.picture != nil }.map(\.id))
        if !taken.isEmpty { commands.insert(.deleteLayers(taken), at: 0) }
        return (.batch(commands, name: "Add Template"), frame.id)
    }

    /// How long a project made from `kind` (New from Template) runs: one
    /// loop at an easy pace, longer for the sequences, which have several
    /// layouts to go through.
    public static func length(of kind: TemplateKind) -> Double {
        library.first { $0.kind == kind }?.group == .sequence ? 16 : 12
    }

    /// A new project holding only a template of `kind`: `composition`'s
    /// size and frame rate, as long as the template's `length`, the frame
    /// filling it and its bar across the whole.
    public static func project(_ kind: TemplateKind, composition: Composition) -> Project {
        var composition = composition
        composition.duration = length(of: kind)
        let frame = frame(kind, filling: composition)
        let bar = Action(target: frame.id, start: 0, duration: composition.duration, easing: .linear,
                         name: name(of: kind), rowOrder: 0, spec: .template(TemplatePlay()))
        return Project(composition: composition, layers: [frame], actions: [bar])
    }

    /// How many steps a loop is cut into when a template is split into
    /// ordinary actions: each step a straight run to where the cards are
    /// next.
    public static let splitSteps = 24

    /// Steps a loop of `kind` is cut into: sequences move many cards a
    /// little after each other between layouts, so they take twice as many.
    public static func splitSteps(for kind: TemplateKind) -> Int {
        Templates.library.first { $0.kind == kind }?.group == .sequence ? splitSteps * 2 : splitSteps
    }

    /// A card's corners, as the Corner Radius action sets them.
    private static func radii(of card: Layer) -> CornerRadii? {
        if case .rectangle(let radii)? = card.look?.geometry { return radii }
        return nil
    }

    /// `angle` turned by whole turns to lie nearest `near`, so a card
    /// going round keeps going the same way rather than spinning back.
    static func nearest(_ angle: Double, to near: Double) -> Double {
        angle + 360 * ((near - angle) / 360).rounded()
    }

    /// The template frame `id` as an ordinary frame in 3D: its cards made
    /// real layers where they rest, and its motion, across its bar, made
    /// To actions from step to step, gathered in a scene named after it.
    /// A card hidden at both ends of a step goes there at once, so the
    /// cards going round the end of a stream do not sweep across. Nil for
    /// anything but a template.
    public static func split(_ id: UUID, in project: Project) -> EditorCommand? {
        guard let frame = project.layer(withID: id), let setup = frame.template else { return nil }
        let pictures = project.pictureSizes
        let bar = project.actions.first { $0.targetLayerID == id && $0.spec.kind == .template }
        let play: TemplatePlay? = if let bar, case .template(let p) = bar.spec, bar.duration > 0 { p } else { nil }
        let steps = play.map { max(Int((Double(splitSteps(for: setup.kind)) * $0.loops).rounded(.up)), 1) } ?? 0
        // Every step's cards, from where it rests, with its settings as its
        // Template Setting actions have them then.
        let tracks = ActionTracks(project.actions)
        var moments = [TemplateCards.make(frame, setup, phase: setup.pose, size: frame.size, pictures: pictures)]
        if let bar, let play {
            for k in stride(from: 1, through: steps, by: 1) {
                let time = bar.start + bar.duration * Double(k) / Double(steps)
                let tuned = setup.tuned(tracks.state(of: frame, at: time).template.settings)
                moments.append(TemplateCards.make(frame, tuned, phase: setup.pose + play.loops * Double(k) / Double(steps),
                                                  size: frame.size, pictures: pictures))
            }
        }
        // A moving Cards setting can show more cards at one step than at
        // another: every card that ever shows is made, unseen while it is
        // not there, so each step has them all.
        let count = moments.map(\.cards.count).max() ?? 0
        for i in 0..<count {
            guard let first = moments.firstIndex(where: { i < $0.cards.count }) else { continue }
            var last = moments[first].cards[i]
            last.opacity = 0
            for m in moments.indices where i >= moments[m].cards.count {
                if m < first {
                    moments[m].cards.append(last)
                } else {
                    var gone = moments[m - 1].cards[i]
                    gone.opacity = 0
                    moments[m].cards.append(gone)
                }
            }
        }
        let rest = moments[0]
        // Real cards, with ids of their own.
        let cards = rest.cards.map { $0.duplicated() }
        let ids = cards.map(\.id)
        var flat = frame
        flat.template = nil
        flat.space3D = rest.space
        flat.children = cards
        var commands: [EditorCommand] = [.updateLayers([flat])]
        var made: [Action] = []
        if let bar, play != nil {
            var row = ActionFactory.nextRowOrder(in: project)
            func add(_ target: UUID, _ start: Double, _ duration: Double, _ spec: ActionSpec) {
                made.append(Action(target: target, start: start, duration: duration, easing: .linear, rowOrder: row, spec: spec))
                row += 1
            }
            // The turns each card was last given, unwound past whole turns.
            var turns = rest.cards.map { ($0.transform.rotation, $0.transform.tilt) }
            for k in stride(from: 1, through: steps, by: 1) {
                let before = moments[k - 1], now = moments[k]
                let t0 = bar.start + bar.duration * Double(k - 1) / Double(steps)
                let length = bar.duration / Double(steps)
                // Worked out as the step's own start is, so a card that goes
                // at once goes exactly as the next step starts.
                let t1 = bar.start + bar.duration * Double(k) / Double(steps)
                if now.space != before.space { add(id, t0, length, .camera(CameraAction(end: now.space))) }
                for (i, (a, b)) in zip(before.cards, now.cards).enumerated() {
                    let hidden = a.opacity < 0.02 && b.opacity < 0.02
                    let (start, duration) = hidden ? (t1, 0.0) : (t0, length)
                    let ta = a.transform, tb = b.transform
                    if ta.position != tb.position { add(ids[i], start, duration, .move(MoveAction(mode: .to, end: tb.position))) }
                    if ta.z != tb.z { add(ids[i], start, duration, .depth(DepthAction(mode: .to, end: tb.z))) }
                    var tilt = tb.tilt
                    tilt.x = nearest(tilt.x, to: turns[i].1.x)
                    tilt.y = nearest(tilt.y, to: turns[i].1.y)
                    let rotation = nearest(tb.rotation, to: turns[i].0)
                    if tilt != turns[i].1 { add(ids[i], start, duration, .tilt(TiltAction(mode: .to, end: tilt))) }
                    if rotation != turns[i].0 { add(ids[i], start, duration, .rotate(RotateAction(mode: .to, end: rotation))) }
                    turns[i] = (rotation, tilt)
                    if ta.scale != tb.scale { add(ids[i], start, duration, .scale(ScaleAction(mode: .to, end: tb.scale))) }
                    if ta.bend != tb.bend { add(ids[i], start, duration, .bend(BendAction(mode: .to, end: tb.bend))) }
                    if a.size != b.size { add(ids[i], start, duration, .resize(ResizeAction(end: b.size))) }
                    if let ra = radii(of: a), let rb = radii(of: b), ra != rb {
                        add(ids[i], start, duration, .cornerRadius(CornerRadiusAction(end: rb)))
                    }
                    if a.opacity != b.opacity { add(ids[i], start, duration, .opacity(OpacityAction(end: b.opacity))) }
                }
            }
        }
        // The bar and the settings it moved, which an ordinary frame has not.
        let gone = project.actions.filter { $0.targetLayerID == id && ($0.spec.kind == .template || $0.spec.kind == .templateSetting) }.map(\.id)
        if !gone.isEmpty { commands.append(.deleteActions(Set(gone))) }
        if !made.isEmpty {
            commands.append(.insertActions(made))
            commands.append(.setScenes(project.scenes + [TimelineScene(name: frame.name, actionIDs: made.map(\.id))]))
        }
        return .batch(commands, name: "Split into Layers")
    }
}
