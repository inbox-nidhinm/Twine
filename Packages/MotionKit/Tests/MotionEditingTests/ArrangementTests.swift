import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private func box(_ name: String, _ x: Double, _ y: Double, _ w: Double = 20, _ h: Double = 20) -> Layer {
    LayerFactory.shape(.rectangle, in: Box(minX: x, minY: y, maxX: x + w, maxY: y + h), name: name, duration: 5)
}

/// Where each of a project's shapes has its corners on screen.
private func corners(_ project: Project, _ ids: [UUID]) -> [[Vec2]] {
    let scene = evaluate(project, at: 0)
    return ids.map { scene.worldCorners(of: $0) ?? [] }
}

private func close(_ a: [[Vec2]], _ b: [[Vec2]]) -> Bool {
    zip(a, b).allSatisfy { pa, pb in zip(pa, pb).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 } }
}

@MainActor
@Suite struct ArrangementTests {
    private func store(_ layers: [Layer]) -> ProjectStore {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return ProjectStore(project: Project(layers: layers), undoManager: undo)
    }

    @Test func groupingKeepsEverythingWhereItWas() throws {
        let a = box("A", 10, 10), b = box("B", 100, 50, 40, 30), c = box("C", 300, 300)
        let s = store([a, b, c])
        let before = corners(s.project, [a.id, b.id])

        let (command, groupID) = try Arrangement.group([b.id, a.id], in: s.project, at: 0, name: "Group 1")
        try s.perform(command)

        #expect(s.project.layers.map(\.name) == ["Group 1", "C"])
        let group = try #require(s.project.layer(withID: groupID))
        #expect(group.children.map(\.name) == ["A", "B"])
        // The group's box is the union of theirs, with its anchor at the middle.
        #expect(group.size.value == Size2(130, 70))
        #expect(group.transform.position.value == Vec2(75, 45))
        #expect(close(corners(s.project, [a.id, b.id]), before))

        s.undoManager.undo()
        #expect(s.project.layers.map(\.name) == ["A", "B", "C"])
    }

    @Test func groupingOnlyWorksWithinOneParent() throws {
        let inner = box("Inner", 0, 0)
        let group = Layer(name: "G", content: .group(GroupContent(children: [inner])), size: Size2(10, 10),
                          position: .zero, outPoint: 5)
        let outer = box("Outer", 50, 50)
        #expect(throws: EditorError.invalidMove) {
            _ = try Arrangement.group([inner.id, outer.id], in: Project(layers: [group, outer]), at: 0, name: "X")
        }
    }

    @Test func ungroupingPutsChildrenBackWhereTheyShow() throws {
        let a = box("A", 10, 10), b = box("B", 100, 50, 40, 30)
        let s = store([a, b])
        let (grouping, groupID) = try Arrangement.group([a.id, b.id], in: s.project, at: 0, name: "G")
        try s.perform(grouping)

        // Turn, scale and fade the group, then take it apart: the children
        // should land exactly where the group was showing them.
        s.project.layer(withID: groupID).map { g in
            var edited = g
            edited.transform.rotation = AnimatableProperty(30)
            edited.transform.scale = AnimatableProperty(Vec2(1.5, 1.5))
            edited.opacity = AnimatableProperty(0.5)
            try? s.perform(.updateLayers([edited]))
        }
        let shown = corners(s.project, [a.id, b.id])
        let (ungrouping, freed) = try Arrangement.ungroup(groupID, in: s.project, at: 0)
        try s.perform(ungrouping)

        #expect(freed == [a.id, b.id])
        #expect(s.project.layers.map(\.name) == ["A", "B"])
        #expect(close(corners(s.project, [a.id, b.id]), shown))
        #expect(abs(s.project.layers[0].opacity.value - 0.5) < 1e-12)
    }

    @Test func restackingMovesThroughSiblings() throws {
        let a = box("A", 0, 0), b = box("B", 0, 0), c = box("C", 0, 0), d = box("D", 0, 0)
        let s = store([a, b, c, d])
        try s.perform(try #require(Arrangement.restack([b.id], .forward, in: s.project)))
        #expect(s.project.layers.map(\.name) == ["A", "C", "B", "D"])
        try s.perform(try #require(Arrangement.restack([b.id], .front, in: s.project)))
        #expect(s.project.layers.map(\.name) == ["A", "C", "D", "B"])
        try s.perform(try #require(Arrangement.restack([b.id], .back, in: s.project)))
        #expect(s.project.layers.map(\.name) == ["B", "A", "C", "D"])
        try s.perform(try #require(Arrangement.restack([c.id], .backward, in: s.project)))
        #expect(s.project.layers.map(\.name) == ["B", "C", "A", "D"])
    }

    @Test func aFailingBatchChangesNothing() throws {
        let a = box("A", 0, 0)
        let s = store([a])
        #expect(throws: EditorError.self) {
            try s.perform(.batch([.renameLayer(a.id, "Renamed"), .renameLayer(UUID(), "Nope")], name: "Both"))
        }
        #expect(s.project.layers[0].name == "A")
    }
}

@Suite struct FactoryTests {
    @Test func shapesFillTheirBoxWithTheAnchorInTheMiddle() {
        let layer = LayerFactory.shape(.ellipse, in: Box(minX: 10, minY: 20, maxX: 110, maxY: 70), name: "E", duration: 3)
        #expect(layer.size.value == Size2(100, 50))
        #expect(layer.transform.position.value == Vec2(60, 45))
        #expect(layer.transform.anchor.value == Vec2(50, 25))
        #expect(layer.outPoint == 3)
    }

    @Test func linesPointFromStartToEnd() {
        let line = LayerFactory.line(from: Vec2(0, 0), to: Vec2(0, 100), name: "L", duration: 5)
        #expect(line.size.value.width == 100)
        #expect(abs(line.transform.rotation.value - 90) < 1e-9)
        let scene = evaluate(Project(layers: [line]), at: 0)
        let ends = scene.worldCorners(of: line.id)!
        #expect(abs(ends[0].x) < 1e-9 && abs(ends[0].y) < 1e-9)
        #expect(abs(ends[1].x) < 1e-9 && abs(ends[1].y - 100) < 1e-9)
    }

    @Test func namesCountUp() {
        let project = Project(layers: [box("Rectangle 1", 0, 0), box("Rectangle 4", 0, 0), box("Ellipse 2", 0, 0)])
        #expect(LayerFactory.nextName("Rectangle", in: project) == "Rectangle 5")
        #expect(LayerFactory.nextName("Star", in: project) == "Star 1")
    }

    @Test func duplicatesGetNewIdentitiesAllTheWayDown() {
        let child = box("Child", 0, 0)
        var masked = box("Masked", 0, 0)
        masked.mask = MaskReference(layerID: child.id)
        let group = Layer(name: "G", content: .group(GroupContent(children: [child, masked])), size: Size2(1, 1),
                          position: .zero, outPoint: 5)
        let copy = group.duplicated()
        #expect(copy.id != group.id)
        #expect(copy.children.map(\.name) == ["Child", "Masked"])
        #expect(copy.children[0].id != child.id)
        // The mask follows the copy of the layer it pointed at.
        #expect(copy.children[1].mask?.layerID == copy.children[0].id)
        if case .shape(let a) = child.content, case .shape(let b) = copy.children[0].content {
            #expect(a.fills[0].id != b.fills[0].id)
        }
    }
}

@Suite struct PropertyEditingTests {
    @Test func staticEditsSetTheValue() {
        let p = AnimatableProperty(Vec2(1, 2)).designEdited(to: Vec2(5, 5), at: 0)
        #expect(p.value == Vec2(5, 5) && !p.isAnimated)
    }

    @Test func animatedEditsShiftTheWholeAnimation() {
        let p = AnimatableProperty(0.0, keyframes: [
            Keyframe(time: 0, value: 0, easing: .linear), Keyframe(time: 2, value: 100),
        ])
        // At t=1 the value is 50; moving it to 60 moves every keyframe by 10.
        let edited = p.designEdited(to: 60, at: 1)
        #expect(edited.keyframes.map(\.value) == [10, 110])
        #expect(abs(edited.value(at: 1) - 60) < 1e-12)
    }

    @Test func translationMovesKeyframesToo() {
        var layer = box("A", 0, 0)
        layer.transform.position = AnimatableProperty(.zero, keyframes: [Keyframe(time: 0, value: Vec2(1, 1))])
        let moved = layer.translated(by: Vec2(10, 0))
        #expect(moved.transform.position.keyframes[0].value == Vec2(11, 1))
    }
}
