import Foundation
import MotionModel
import MotionEvaluation

/// The headed groups the template picker shows, in order.
public enum TemplateGroup: String, Sendable, CaseIterable {
    case perspective, isometric, orbit, flow, grid, spotlight, reveal, stack

    public var title: String {
        switch self {
        case .perspective: "3D & Perspective"
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

    /// How many steps a loop is cut into when a template is split into
    /// ordinary actions: each step a straight run to where the cards are
    /// next.
    public static let splitSteps = 24

    /// The template frame `id` as an ordinary frame in 3D: its cards made
    /// real layers where they rest, and its motion, across its bar, made
    /// To actions from step to step, gathered in a scene named after it.
    /// A card hidden at both ends of a step goes there at once, so the
    /// cards going round the end of a stream do not sweep across. Nil for
    /// anything but a template.
    public static func split(_ id: UUID, in project: Project) -> EditorCommand? {
        guard let frame = project.layer(withID: id), let setup = frame.template else { return nil }
        let pictures = project.pictureSizes
        let rest = TemplateCards.make(frame, setup, phase: setup.pose, size: frame.size, pictures: pictures)
        // Real cards, with ids of their own.
        let cards = rest.cards.map { $0.duplicated() }
        let ids = cards.map(\.id)
        var flat = frame
        flat.template = nil
        flat.space3D = rest.space
        flat.children = cards
        var commands: [EditorCommand] = [.updateLayers([flat])]
        let bar = project.actions.first { $0.targetLayerID == id && $0.spec.kind == .template }
        var made: [Action] = []
        if let bar, case .template(let play) = bar.spec, bar.duration > 0 {
            var row = ActionFactory.nextRowOrder(in: project)
            func add(_ target: UUID, _ start: Double, _ duration: Double, _ spec: ActionSpec) {
                made.append(Action(target: target, start: start, duration: duration, easing: .linear, rowOrder: row, spec: spec))
                row += 1
            }
            let steps = max(Int((Double(splitSteps) * play.loops).rounded(.up)), 1)
            var before = rest
            for k in 1...steps {
                let phase = setup.pose + play.loops * Double(k) / Double(steps)
                let now = TemplateCards.make(frame, setup, phase: phase, size: frame.size, pictures: pictures)
                let t0 = bar.start + bar.duration * Double(k - 1) / Double(steps)
                let length = bar.duration / Double(steps)
                if now.space != before.space { add(id, t0, length, .camera(CameraAction(end: now.space))) }
                for (i, (a, b)) in zip(before.cards, now.cards).enumerated() {
                    let hidden = a.opacity < 0.02 && b.opacity < 0.02
                    let (start, duration) = hidden ? (t0 + length, 0.0) : (t0, length)
                    let ta = a.transform, tb = b.transform
                    if ta.position != tb.position { add(ids[i], start, duration, .move(MoveAction(mode: .to, end: tb.position))) }
                    if ta.z != tb.z { add(ids[i], start, duration, .depth(DepthAction(mode: .to, end: tb.z))) }
                    if ta.tilt != tb.tilt { add(ids[i], start, duration, .tilt(TiltAction(mode: .to, end: tb.tilt))) }
                    if ta.rotation != tb.rotation { add(ids[i], start, duration, .rotate(RotateAction(mode: .to, end: tb.rotation))) }
                    if ta.scale != tb.scale { add(ids[i], start, duration, .scale(ScaleAction(mode: .to, end: tb.scale))) }
                    if ta.bend != tb.bend { add(ids[i], start, duration, .bend(BendAction(mode: .to, end: tb.bend))) }
                    if a.opacity != b.opacity { add(ids[i], start, duration, .opacity(OpacityAction(end: b.opacity))) }
                }
                before = now
            }
            commands.append(.deleteActions([bar.id]))
            if !made.isEmpty {
                commands.append(.insertActions(made))
                commands.append(.setScenes(project.scenes + [TimelineScene(name: frame.name, actionIDs: made.map(\.id))]))
            }
        }
        return .batch(commands, name: "Split into Layers")
    }
}
