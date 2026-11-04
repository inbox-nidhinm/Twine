import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// The Z-Index action: a layer drawn in front of or behind its siblings from
/// a moment on, while the layers' own order stays as designed.
@Suite struct ZIndexTests {
    static func card(_ name: String) -> Layer {
        Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                       fills: [Fill(paint: .solid(.black))])),
              size: Size2(100, 80), position: Vec2(200, 150))
    }

    static func zIndex(_ layer: Layer, _ index: Int, at start: Double) -> Action {
        Action(target: layer.id, start: start, duration: 0, spec: .zIndex(ZIndexAction(index: index)))
    }

    static func names(_ scene: ResolvedScene, _ named: [UUID: String]) -> [String] {
        scene.drawingOrder().map { named[scene.layers[$0].id] ?? "?" }
    }

    @Test func aLayerIsAtZeroUntilItsActionStarts() {
        let a = Self.card("A")
        let tracks = ActionTracks([Self.zIndex(a, 3, at: 1), Self.zIndex(a, -2, at: 2)])
        #expect(tracks.state(of: a, at: 0.5).zIndex == 0)
        #expect(tracks.state(of: a, at: 1).zIndex == 3)
        #expect(tracks.state(of: a, at: 1.5).zIndex == 3)
        #expect(tracks.state(of: a, at: 2.5).zIndex == -2)
    }

    @Test func itIsAlwaysInstant() {
        let a = Self.card("A")
        // Even given a length, it changes at its start, not part way.
        var long = Self.zIndex(a, 4, at: 1)
        long.duration = 2
        #expect(long.isInstant)
        #expect(ActionTracks([long]).state(of: a, at: 1.01).zIndex == 4)
    }

    @Test func aHigherNumberIsDrawnInFrontOfItsSiblings() {
        let a = Self.card("A"), b = Self.card("B"), c = Self.card("C")
        let named = [a.id: "A", b.id: "B", c.id: "C"]
        // A is at the back of the list; from 1 s it comes in front.
        let p = Project(layers: [a, b, c], actions: [Self.zIndex(a, 1, at: 1)])
        #expect(Self.names(evaluate(p, at: 0.5), named) == ["A", "B", "C"])
        #expect(Self.names(evaluate(p, at: 1.5), named) == ["B", "C", "A"])
        // The layers themselves never move.
        #expect(evaluate(p, at: 1.5).layers.map(\.id) == [a.id, b.id, c.id])
        // Below zero goes behind.
        let back = Project(layers: [a, b, c], actions: [Self.zIndex(c, -1, at: 0)])
        #expect(Self.names(evaluate(back, at: 0), named) == ["C", "A", "B"])
        // The same number keeps the list's order.
        let tie = Project(layers: [a, b, c], actions: [Self.zIndex(a, 2, at: 0), Self.zIndex(b, 2, at: 0)])
        #expect(Self.names(evaluate(tie, at: 0), named) == ["C", "A", "B"])
    }

    @Test func itOrdersOnlyAmongTheLayersBesideIt() {
        let a = Self.card("A"), b = Self.card("B"), outside = Self.card("Out")
        let group = Layer(name: "G", content: .group(GroupContent(children: [a, b])), size: Size2(400, 300), position: Vec2(200, 150))
        let named = [a.id: "A", b.id: "B", outside.id: "Out", group.id: "G"]
        // A huge number puts A in front of B, but still inside its group,
        // which is behind Out.
        let p = Project(layers: [group, outside], actions: [Self.zIndex(a, 100, at: 0)])
        #expect(Self.names(evaluate(p, at: 0), named) == ["G", "B", "A", "Out"])
        // The group moves with everything in it.
        let g = Project(layers: [outside, group], actions: [Self.zIndex(group, -1, at: 0)])
        #expect(Self.names(evaluate(g, at: 0), named) == ["G", "A", "B", "Out"])
    }

    @Test func aFrameIn3DIgnoresIt() {
        var a = Self.card("A"), b = Self.card("B")
        a.transform.z = 10
        b.transform.z = 0
        let frame = Layer(name: "F", content: .group(GroupContent(children: [a, b], frame: FrameStyle(space: Space3D(distance: 1000)))),
                          size: Size2(400, 300), position: Vec2(200, 150))
        let p = Project(layers: [frame], actions: [Self.zIndex(b, 5, at: 0)])
        let s = evaluate(p, at: 0)
        #expect(s.layer(b.id)?.zIndex == 0)
        // Depth decides: A, nearer, stays in front.
        #expect(Self.names(s, [a.id: "A", b.id: "B", frame.id: "F"]) == ["F", "B", "A"])
    }

    @Test func itIsSavedAndReadBack() throws {
        let a = Self.card("A")
        let action = Self.zIndex(a, -7, at: 1.5)
        let data = try JSONEncoder().encode(action)
        #expect(try JSONDecoder().decode(Action.self, from: data) == action)
    }
}
