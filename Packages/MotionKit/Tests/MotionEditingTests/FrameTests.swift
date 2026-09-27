import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct FrameTests {
    private func square(_ name: String, at x: Double, _ y: Double, size: Double = 20) -> Layer {
        var l = LayerFactory.shape(.rectangle, in: Box(origin: Vec2(x, y), size: Size2(size, size)), name: name)
        l.name = name
        return l
    }

    @Test func aNewFrameIsWhiteAndClips() {
        let frame = LayerFactory.frame(in: Box(origin: Vec2(10, 20), size: Size2(100, 50)), name: "Frame 1")
        #expect(frame.isFrame && frame.isGroup)
        #expect(frame.look?.fills.map(\.paint) == [.color(.white)])
        #expect(frame.look?.geometry == .rectangle(cornerRadii: .zero))
        guard case .group(let g) = frame.content else { return }
        #expect(g.clipsContent)
        #expect(frame.size == Size2(100, 50) && frame.transform.position == Vec2(60, 45))
    }

    @Test func aFramesLookIsARectangleThatCanBeRestyled() {
        var frame = LayerFactory.frame(in: Box(origin: .zero, size: Size2(10, 10)), name: "F")
        var look = frame.look!
        look.fills = [Fill(paint: .color(.black))]
        look.geometry = .rectangle(cornerRadii: CornerRadii(all: 3))
        frame.look = look
        guard case .group(let g) = frame.content else { return }
        #expect(g.frame?.cornerRadii == CornerRadii(all: 3))
        #expect(g.frame?.fills.map(\.paint) == [.color(.black)])
    }

    @Test func framingLayersKeepsThemInPlaceWithTheirActions() throws {
        let a = square("a", at: 100, 100), b = square("b", at: 150, 120)
        let move = Action(target: a.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .to, end: Vec2(300, 300))))
        var project = Project(layers: [a, b], actions: [move])
        let (command, frameID) = try Arrangement.group([a.id, b.id], in: project, name: "Frame 1", asFrame: true)
        try command.apply(to: &project)
        let frame = try #require(project.layer(withID: frameID))
        #expect(frame.isFrame && frame.children.map(\.id) == [a.id, b.id])
        #expect(Arrangement.box(of: frame) == Box(minX: 100, minY: 100, maxX: 170, maxY: 140))
        // The frame's top-left is (100, 100), so a's centre (110, 110) is
        // (10, 10) inside it, and its move's end comes along.
        #expect(project.layer(withID: a.id)?.transform.position == Vec2(10, 10))
        #expect(project.actions.first?.spec == .move(MoveAction(mode: .to, end: Vec2(200, 200))))
        #expect(project.layers.map(\.id) == [frameID])
    }

    @Test func groupingKeepsAMaskThatPointsInside() throws {
        let source = square("mask", at: 0, 0), other = square("other", at: 30, 0)
        var masked = square("masked", at: 60, 0)
        masked.mask = MaskReference(layerID: source.id)
        var project = Project(layers: [source, other, masked])
        let (command, _) = try Arrangement.group([source.id, other.id], in: project, name: "Group 1")
        try command.apply(to: &project)
        #expect(project.layer(withID: masked.id)?.mask?.layerID == source.id)
    }

    @Test func aFrameDrawnAroundLayersTakesInTheWholeOnesBehindIt() throws {
        let inside = square("in", at: 20, 20), across = square("across", at: 100, 20), locked = { () -> Layer in
            var l = square("locked", at: 30, 30)
            l.isLocked = true
            return l
        }()
        let frame = LayerFactory.frame(in: Box(origin: Vec2(10, 10), size: Size2(100, 100)), name: "Frame 1")
        let above = square("above", at: 40, 40)
        var project = Project(layers: [inside, across, locked, frame, above])
        #expect(Arrangement.enclosed(by: frame.id, in: project) == [inside.id])
        let command = try #require(Arrangement.adopt([inside.id], into: frame.id, in: project))
        try command.apply(to: &project)
        #expect(project.layer(withID: frame.id)?.children.map(\.id) == [inside.id])
        // (30, 30) in the composition is (20, 20) in the frame.
        #expect(project.layer(withID: inside.id)?.transform.position == Vec2(20, 20))
    }

    @Test func aFrameOffersWhatARectangleDoes() {
        let frame = LayerFactory.frame(in: Box(origin: .zero, size: Size2(10, 10)), name: "F")
        let kinds = ActionFactory.kinds(for: frame, hasSound: false)
        for kind: ActionKind in [.resize, .color, .cornerRadius, .shadow, .backgroundBlur] { #expect(kinds.contains(kind)) }
        let group = LayerFactory.group(in: Box(origin: .zero, size: Size2(10, 10)), children: [], name: "G")
        #expect(!ActionFactory.kinds(for: group, hasSound: false).contains(.resize))
    }

    @Test func aFramesColourAndCornersAnimateAndItsBoxIsItsOwn() {
        var frame = LayerFactory.frame(in: Box(origin: .zero, size: Size2(100, 100)), name: "F")
        frame.children = [square("far", at: 300, 300)]
        let colour = Action(target: frame.id, start: 0, duration: 1, easing: .linear,
                            spec: .color(ColorAction(end: .color(.black))))
        let corners = Action(target: frame.id, start: 0, duration: 1, easing: .linear,
                             spec: .cornerRadius(CornerRadiusAction(end: CornerRadii(all: 20))))
        let scene = evaluate(Project(layers: [frame], actions: [colour, corners]), at: 1)
        let resolved = scene.layer(frame.id)
        #expect(resolved?.frame?.fills == [.solid(.black)])
        #expect(resolved?.frame?.path == ShapeGeometry.rectangle(cornerRadii: CornerRadii(all: 20)).bezierPath(size: Size2(100, 100)))
        #expect(scene.bounds(of: frame.id) == Box(minX: 0, minY: 0, maxX: 100, maxY: 100))
    }

    @Test func movingALayerIntoAFrameKeepsItOnScreen() throws {
        var frame = LayerFactory.frame(in: Box(origin: Vec2(100, 100), size: Size2(200, 200)), name: "F")
        frame.transform.rotation = 90
        let a = square("a", at: 150, 150)
        let move = Action(target: a.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .to, end: Vec2(210, 160))))
        var project = Project(layers: [a, frame], actions: [move])
        let before = evaluate(project, at: 0).worldCorners(of: a.id)!
        let beforeEnd = evaluate(project, at: 1).worldCorners(of: a.id)!
        try Arrangement.move([a.id], to: frame.id, index: nil, in: project).apply(to: &project)
        #expect(project.location(of: a.id)?.parentID == frame.id)
        func near(_ p: [Vec2], _ q: [Vec2]) -> Bool { zip(p, q).allSatisfy { abs($0.x - $1.x) < 1e-6 && abs($0.y - $1.y) < 1e-6 } }
        #expect(near(evaluate(project, at: 0).worldCorners(of: a.id)!, before))
        #expect(near(evaluate(project, at: 1).worldCorners(of: a.id)!, beforeEnd))
        // And back out again.
        try Arrangement.move([a.id], to: nil, index: nil, in: project).apply(to: &project)
        #expect(near(evaluate(project, at: 0).worldCorners(of: a.id)!, before))
    }

    @Test func groupsSavedBeforeFramesStillOpen() throws {
        let json = #"{"children": [], "clipsContent": true}"#
        #expect(try JSONDecoder().decode(GroupContent.self, from: Data(json.utf8)) == GroupContent(clipsContent: true))
    }
}
