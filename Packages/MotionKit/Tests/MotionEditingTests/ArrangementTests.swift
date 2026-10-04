import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private func box(_ name: String, _ x: Double, _ y: Double, _ w: Double = 20, _ h: Double = 20) -> Layer {
    LayerFactory.shape(.rectangle, in: Box(minX: x, minY: y, maxX: x + w, maxY: y + h), name: name)
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

        let (command, groupID) = try Arrangement.group([b.id, a.id], in: s.project, name: "Group 1")
        try s.perform(command)

        #expect(s.project.layers.map(\.name) == ["Group 1", "C"])
        let group = try #require(s.project.layer(withID: groupID))
        #expect(group.children.map(\.name) == ["A", "B"])
        // The group's box is the union of theirs, with its anchor at the middle.
        #expect(group.size == Size2(130, 70))
        #expect(group.transform.position == Vec2(75, 45))
        #expect(close(corners(s.project, [a.id, b.id]), before))

        s.undoManager.undo()
        #expect(s.project.layers.map(\.name) == ["A", "B", "C"])
    }

    @Test func groupingOnlyWorksWithinOneParent() throws {
        let inner = box("Inner", 0, 0)
        let group = Layer(name: "G", content: .group(GroupContent(children: [inner])), size: Size2(10, 10),
                          position: .zero)
        let outer = box("Outer", 50, 50)
        #expect(throws: EditorError.invalidMove) {
            _ = try Arrangement.group([inner.id, outer.id], in: Project(layers: [group, outer]), name: "X")
        }
    }

    @Test func ungroupingPutsChildrenBackWhereTheyShow() throws {
        let a = box("A", 10, 10), b = box("B", 100, 50, 40, 30)
        let s = store([a, b])
        let (grouping, groupID) = try Arrangement.group([a.id, b.id], in: s.project, name: "G")
        try s.perform(grouping)

        // Turn, scale and fade the group, then take it apart: the children
        // should land exactly where the group was showing them.
        s.project.layer(withID: groupID).map { g in
            var edited = g
            edited.transform.rotation = 30
            edited.transform.scale = Vec2(1.5, 1.5)
            edited.opacity = 0.5
            try? s.perform(.updateLayers([edited]))
        }
        let shown = corners(s.project, [a.id, b.id])
        let (ungrouping, freed) = try Arrangement.ungroup(groupID, in: s.project)
        try s.perform(ungrouping)

        #expect(freed == [a.id, b.id])
        #expect(s.project.layers.map(\.name) == ["A", "B"])
        #expect(close(corners(s.project, [a.id, b.id]), shown))
        #expect(abs(s.project.layers[0].opacity - 0.5) < 1e-12)
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
        let layer = LayerFactory.shape(.ellipse, in: Box(minX: 10, minY: 20, maxX: 110, maxY: 70), name: "E")
        #expect(layer.size == Size2(100, 50))
        #expect(layer.transform.position == Vec2(60, 45))
        #expect(layer.transform.anchor == Vec2(50, 25))
    }

    @Test func linesPointFromStartToEnd() {
        let line = LayerFactory.line(from: Vec2(0, 0), to: Vec2(0, 100), name: "L")
        #expect(line.size.width == 100)
        #expect(abs(line.transform.rotation - 90) < 1e-9)
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
        var child = box("Child", 0, 0)
        child.isMask = true
        let masked = box("Masked", 0, 0)
        let group = Layer(name: "G", content: .group(GroupContent(children: [child, masked])), size: Size2(1, 1),
                          position: .zero)
        let copy = group.duplicated()
        #expect(copy.id != group.id)
        #expect(copy.children.map(\.name) == ["Child", "Masked"])
        #expect(copy.children[0].id != child.id)
        // The mask is a mask in the copy too.
        #expect(copy.children[0].isMask && !copy.children[1].isMask)
        if case .shape(let a) = child.content, case .shape(let b) = copy.children[0].content {
            #expect(a.fills[0].id != b.fills[0].id)
        }
    }
}

@MainActor
@Suite struct ActionEditingTests {
    private func store(_ layers: [Layer], _ actions: [Action] = []) -> ProjectStore {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return ProjectStore(project: Project(layers: layers, actions: actions), undoManager: undo)
    }

    private func moveTo(_ layer: Layer, _ end: Vec2) -> Action {
        Action(target: layer.id, start: 0, duration: 1, easing: .linear, spec: .move(MoveAction(mode: .to, end: end)))
    }

    @Test func actionsAreAddedChangedAndDeletedWithUndo() throws {
        let a = box("A", 0, 0)
        let s = store([a])
        var action = moveTo(a, Vec2(50, 50))
        try s.perform(.insertActions([action]))
        #expect(s.project.actions == [action])
        action.start = 2
        try s.perform(.updateActions([action]))
        #expect(s.project.actions[0].start == 2)
        try s.perform(.deleteActions([action.id]))
        #expect(s.project.actions.isEmpty)
        s.undoManager.undo()
        s.undoManager.undo()
        #expect(s.project.actions[0].start == 0)
    }

    @Test func anActionMustAimAtALayerThatExists() {
        let a = box("A", 0, 0)
        let s = store([a])
        #expect(throws: EditorError.self) { try s.perform(.insertActions([moveTo(box("Ghost", 0, 0), .zero)])) }
        var negative = moveTo(a, .zero)
        negative.duration = -1
        #expect(throws: EditorError.invalidValue) { try s.perform(.insertActions([negative])) }
        #expect(s.project.actions.isEmpty)
    }

    @Test func deletingALayerDeletesItsActions() throws {
        let a = box("A", 0, 0), b = box("B", 0, 0)
        let child = box("Child", 0, 0)
        let group = LayerFactory.group(in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), children: [child], name: "G")
        let s = store([a, b, group], [moveTo(a, .zero), moveTo(b, .zero), moveTo(child, .zero)])
        try s.perform(.deleteLayers([a.id, group.id]))
        #expect(s.project.actions.map(\.targetLayerID) == [b.id])
        s.undoManager.undo()
        #expect(s.project.actions.count == 3)
    }

    @Test func groupingKeepsToMovesOnScreen() throws {
        let a = box("A", 100, 100)
        let s = store([a], [moveTo(a, Vec2(400, 300))])
        let before = evaluate(s.project, at: 1).worldCorners(of: a.id)!
        let (command, _) = try Arrangement.group([a.id], in: s.project, name: "G")
        try s.perform(command)
        let after = evaluate(s.project, at: 1).worldCorners(of: a.id)!
        #expect(zip(before, after).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 })
        #expect(s.project.actions.count == 1)
    }

    @Test func ungroupingCarriesChildActionsAndDropsTheGroups() throws {
        let a = box("A", 10, 10), b = box("B", 100, 50, 40, 30)
        let s = store([a, b])
        let (grouping, groupID) = try Arrangement.group([a.id, b.id], in: s.project, name: "G")
        try s.perform(grouping)
        let child = try #require(s.project.layer(withID: a.id))
        try s.perform(.insertActions([moveTo(child, Vec2(20, 30))]))
        s.project.layer(withID: groupID).map { g in
            var edited = g
            edited.transform.rotation = 30
            try? s.perform(.updateLayers([edited]))
        }
        // Where the child shows with the group as designed, before the group
        // gets an action of its own.
        let shown = evaluate(s.project, at: 1).worldCorners(of: a.id)!
        let groupSpin = Action(target: groupID, start: 0, duration: 1, spec: .rotate(RotateAction(end: 90)))
        try s.perform(.insertActions([groupSpin]))
        let (ungrouping, _) = try Arrangement.ungroup(groupID, in: s.project)
        try s.perform(ungrouping)
        // The group's own spin goes with the group; the child's move lands
        // where the group's designed transform was showing it.
        #expect(s.project.actions.map(\.targetLayerID) == [a.id])
        let after = evaluate(s.project, at: 1).worldCorners(of: a.id)!
        #expect(zip(shown, after).allSatisfy { abs($0.x - $1.x) < 1e-9 && abs($0.y - $1.y) < 1e-9 })
    }

    @Test func duplicatesBringTheirActions() {
        let child = box("Child", 0, 0)
        let group = LayerFactory.group(in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), children: [child], name: "G")
        let spin = Action(target: group.id, start: 1, duration: 1, spec: .rotate(RotateAction(end: 90)))
        let project = Project(layers: [group], actions: [spin, moveTo(child, .zero)])
        var map: [UUID: UUID] = [:]
        let copy = group.duplicated(recordingIDs: &map)
        let copies = project.actionCopies(for: map)
        #expect(copies.count == 2)
        #expect(Set(copies.map(\.targetLayerID)) == [copy.id, copy.children[0].id])
        #expect(Set(copies.map(\.id)).isDisjoint(with: [spin.id]))
        #expect(copies.first { $0.targetLayerID == copy.id }?.spec == spin.spec)
    }

    @Test func translationMovesTheDesignPosition() {
        let layer = box("A", 0, 0)
        let moved = layer.translated(by: Vec2(10, 0))
        #expect(moved.transform.position == Vec2(20, 10))
    }
}
