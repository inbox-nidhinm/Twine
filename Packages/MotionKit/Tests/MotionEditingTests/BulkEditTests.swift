import Foundation
import Testing
import MotionModel
@testable import MotionEditing

/// Edits of many things at once take a faster road than a few do: both
/// must end in the same place.
@Suite struct BulkEditTests {
    private func shape(_ name: String, at x: Double) -> Layer {
        Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero))),
              size: Size2(40, 30), position: Vec2(x, 20))
    }

    private func group(_ name: String, _ children: [Layer], turn: Double = 0, scale: Double = 1) -> Layer {
        var g = Layer(name: name, content: .group(GroupContent(children: children)), size: Size2(400, 200),
                      position: Vec2(300, 150))
        g.transform.rotation = turn
        g.transform.scale = Vec2(scale, scale)
        return g
    }

    /// Three groups (one turned and scaled, one holding a group of its
    /// own) and a few loose layers: thirty-odd layers in all.
    private func project() -> Project {
        let inner = group("Inner", (0..<4).map { shape("I\($0)", at: Double($0) * 50) }, turn: 15)
        let a = group("A", (0..<6).map { shape("A\($0)", at: Double($0) * 50) })
        let b = group("B", (0..<6).map { shape("B\($0)", at: Double($0) * 50) } + [inner], turn: 30, scale: 1.5)
        let c = group("C", (0..<6).map { shape("C\($0)", at: Double($0) * 50) }, scale: 0.5)
        return Project(layers: [a, shape("Loose 1", at: 10), b, c, shape("Loose 2", at: 90)])
    }

    private func leaves(_ project: Project) -> [Layer] {
        var out: [Layer] = []
        project.forEachLayer { if !$0.isGroup { out.append($0) } }
        return out
    }

    @Test func manyActionsGoInAndChangeAsAFewDo() throws {
        let start = project()
        let actions = leaves(start).enumerated().flatMap { i, layer in
            (0..<3).map { k in
                Action(target: layer.id, start: Double(k), duration: 1, rowOrder: i * 3 + k,
                       spec: .move(MoveAction(mode: .by, end: Vec2(Double(i), 0))))
            }
        }
        var atOnce = start, inFews = start
        try EditorCommand.insertActions(actions).apply(to: &atOnce)
        for from in stride(from: 0, to: actions.count, by: 5) {
            try EditorCommand.insertActions(Array(actions[from..<min(from + 5, actions.count)])).apply(to: &inFews)
        }
        #expect(atOnce == inFews)

        let shifted = actions.reversed().map { a -> Action in var b = a; b.start += 0.25; return b }
        try EditorCommand.updateActions(shifted).apply(to: &atOnce)
        for from in stride(from: 0, to: shifted.count, by: 5) {
            try EditorCommand.updateActions(Array(shifted[from..<min(from + 5, shifted.count)])).apply(to: &inFews)
        }
        #expect(atOnce == inFews)

        // And what is refused of a few is refused of many.
        var again = atOnce
        #expect(throws: EditorError.self) { try EditorCommand.insertActions(actions).apply(to: &again) }
        // New actions, one of them for a layer that is not there.
        let stray = actions.enumerated().map { i, a in
            Action(target: i == 20 ? UUID() : a.targetLayerID, start: a.start, duration: a.duration, rowOrder: a.rowOrder, spec: a.spec)
        }
        #expect(throws: EditorError.self) { try EditorCommand.insertActions(stray).apply(to: &again) }
        // And a change to an action that is not there.
        var unknown = shifted
        unknown[11] = Action(target: shifted[11].targetLayerID, start: 0, duration: 1, spec: shifted[11].spec)
        #expect(throws: EditorError.self) { try EditorCommand.updateActions(unknown).apply(to: &again) }
        #expect(again == atOnce)
    }

    @Test func manyLayersChangeAsAFewDo() throws {
        let start = project()
        let edited = leaves(start).map { layer -> Layer in
            var l = layer
            l.opacity = 0.5
            l.transform.position.x += 3
            return l
        }
        var atOnce = start, inFews = start
        try EditorCommand.updateLayers(edited).apply(to: &atOnce)
        for from in stride(from: 0, to: edited.count, by: 4) {
            try EditorCommand.updateLayers(Array(edited[from..<min(from + 4, edited.count)])).apply(to: &inFews)
        }
        #expect(atOnce == inFews)

        // A group and layers inside it in one list go one by one, in the
        // order given, as before.
        var withGroup = edited
        var b = try #require(atOnce.layers.first { $0.name == "B" })
        b.name = "B renamed"
        withGroup.insert(b, at: 0)
        var whole = atOnce, oneByOne = atOnce
        try EditorCommand.updateLayers(withGroup).apply(to: &whole)
        for layer in withGroup { try EditorCommand.updateLayers([layer]).apply(to: &oneByOne) }
        #expect(whole == oneByOne)

        var missing = edited
        missing[5] = shape("Nobody", at: 0)
        var untouched = start
        #expect(throws: EditorError.self) { try EditorCommand.updateLayers(missing).apply(to: &untouched) }
        #expect(untouched == start)
    }

    /// Where a layer's anchor sits in the composition.
    private func place(of id: UUID, in project: Project) -> Vec2? {
        guard let layer = project.layer(withID: id) else { return nil }
        return Arrangement.designWorld(of: project.location(of: id)?.parentID, in: project).apply(layer.transform.position)
    }

    @Test func manyLayersMoveOutTogetherStayingWhereTheyAre() throws {
        let start = project()
        // Every layer of B (its inner group among them, and that group's own
        // layers, which travel with it) and every layer of C.
        let b = try #require(start.layers.first { $0.name == "B" }), c = try #require(start.layers.first { $0.name == "C" })
        let inner = try #require(b.children.first { $0.name == "Inner" })
        let asked = b.children.map(\.id) + inner.children.map(\.id) + c.children.map(\.id)
        var moved = start
        try Arrangement.move(asked, to: nil, index: nil, in: start).apply(to: &moved)

        // In front of everything, in the order they stood in.
        let names = moved.layers.map(\.name)
        #expect(Array(names.suffix(13)) == (0..<6).map { "B\($0)" } + ["Inner"] + (0..<6).map { "C\($0)" })
        #expect(moved.layers.first { $0.name == "B" }?.children.isEmpty == true)
        // The inner group went whole, with its layers still inside it.
        #expect(moved.layers.first { $0.name == "Inner" }?.children.map(\.name) == (0..<4).map { "I\($0)" })
        // And nothing moved on the canvas.
        for id in asked {
            let before = try #require(place(of: id, in: start)), after = try #require(place(of: id, in: moved))
            #expect(abs(before.x - after.x) < 1e-6 && abs(before.y - after.y) < 1e-6)
        }

        // The same move, asked for a few layers at a time, ends the same.
        var inFews = start
        for from in stride(from: 0, to: asked.count, by: 6) {
            let few = Array(asked[from..<min(from + 6, asked.count)])
            try Arrangement.move(few, to: nil, index: nil, in: inFews).apply(to: &inFews)
        }
        for id in asked {
            let a = try #require(place(of: id, in: moved)), f = try #require(place(of: id, in: inFews))
            #expect(abs(a.x - f.x) < 1e-6 && abs(a.y - f.y) < 1e-6)
        }
    }

    /// A name with a number past any count does not stop the next name
    /// being made.
    @Test func aHugeNumberInANameIsPassedOver() {
        let project = Project(layers: [shape("Rectangle 9223372036854775807", at: 0), shape("Rectangle 4", at: 0), shape("Rectangle", at: 0)])
        #expect(LayerFactory.nextName("Rectangle", in: project) == "Rectangle 5")
        #expect(LayerFactory.nextName("Ellipse", in: project) == "Ellipse 1")
    }
}
