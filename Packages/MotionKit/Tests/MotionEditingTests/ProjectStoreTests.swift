import Foundation
import Testing
import MotionModel
@testable import MotionEditing

@MainActor
@Suite struct ProjectStoreTests {
    private func shape(_ name: String) -> Layer {
        Layer(name: name, content: .shape(ShapeContent(geometry: .ellipse(arc: .full))),
              size: Size2(10, 10), position: .zero)
    }

    /// Grouping by event needs a running event loop, which tests do not have.
    /// The store opens and closes its own groups, so nothing else changes.
    private func makeStore(_ project: Project = Project(), budget: Int = ProjectStore.undoBudget) -> ProjectStore {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return ProjectStore(project: project, undoManager: undo, undoBudget: budget)
    }

    private func undoCount(_ store: ProjectStore) -> Int {
        var n = 0
        while store.undoManager.canUndo { store.undoManager.undo(); n += 1 }
        return n
    }

    @Test func atMostTwoHundredStepsCanBeUndone() throws {
        let store = makeStore()
        let a = shape("A")
        try store.perform(.insertLayers([a], parentID: nil, index: nil))
        for i in 0..<210 { try store.perform(.renameLayer(a.id, "N\(i)")) }
        #expect(undoCount(store) == ProjectStore.undoSteps)
        // The oldest went: the layer is still there, named by the tenth rename.
        #expect(store.project.layers.map(\.name) == ["N9"])
    }

    @Test func theOldestStepsGoWhenTheHistoryOutgrowsItsBudget() throws {
        let a = shape("A")
        let step = ProjectStore.cost(of: Project(layers: [a]), against: Project(layers: [shape("B")]))
        // Room for five renames of a one-layer project.
        let store = makeStore(Project(layers: [a]), budget: step * 5)
        for i in 0..<12 { try store.perform(.renameLayer(a.id, "N\(i)")) }
        #expect(undoCount(store) == 5)
        #expect(store.project.layers.map(\.name) == ["N6"])
        // Redo still runs the whole way back.
        var redone = 0
        while store.undoManager.canRedo { store.undoManager.redo(); redone += 1 }
        #expect(redone == 5)
        #expect(store.project.layers.map(\.name) == ["N11"])
    }

    @Test func commandsUndoAndRedo() throws {
        let store = makeStore()
        let a = shape("A")
        try store.perform(.insertLayers([a], parentID: nil, index: nil))
        try store.perform(.renameLayer(a.id, "Renamed"))
        #expect(store.project.layers.map(\.name) == ["Renamed"])
        #expect(store.undoManager.undoActionName == "Rename Layer")

        store.undoManager.undo()
        #expect(store.project.layers.map(\.name) == ["A"])
        store.undoManager.undo()
        #expect(store.project.layers.isEmpty)

        store.undoManager.redo()
        store.undoManager.redo()
        #expect(store.project.layers.map(\.name) == ["Renamed"])
    }

    @Test func aFoldingChangeTakesPlainCommandsAsOneStep() throws {
        let store = makeStore()
        let a = shape("A")
        try store.perform(.insertLayers([a], parentID: nil, index: nil))
        store.beginContinuousChange("Change Value", folding: true)
        for name in ["B", "C", "D"] { try store.perform(.renameLayer(a.id, name)) }
        store.endContinuousChange()
        #expect(store.project.layers.map(\.name) == ["D"])
        #expect(store.undoManager.undoActionName == "Change Value")
        store.undoManager.undo()
        #expect(store.project.layers.map(\.name) == ["A"])
        // Once it ends, commands are their own steps again.
        try store.perform(.renameLayer(a.id, "E"))
        store.undoManager.undo()
        #expect(store.project.layers.map(\.name) == ["A"])
    }

    @Test func aCommandThatChangesNothingRecordsNothing() throws {
        let a = shape("A")
        let store = makeStore(Project(layers: [a]))
        try store.perform(.setVisible([a.id], true))
        #expect(!store.undoManager.canUndo)
    }

    @Test func aFailingCommandLeavesTheProjectAlone() {
        let a = shape("A")
        let store = makeStore(Project(layers: [a]))
        #expect(throws: EditorError.self) {
            try store.perform(.renameLayer(UUID(), "X"))
        }
        #expect(store.project.layers == [a])
        #expect(!store.undoManager.canUndo)
    }

    @Test func continuousChangesUndoAsOneStep() throws {
        var a = shape("A")
        let store = makeStore(Project(layers: [a]))
        store.beginContinuousChange("Move")
        for x in stride(from: 0.0, through: 100, by: 10) {
            a.transform.position = Vec2(x, 0)
            try store.updateContinuousChange(.updateLayers([a]))
        }
        store.endContinuousChange()
        #expect(store.project.layers[0].transform.position == Vec2(100, 0))

        store.undoManager.undo()
        #expect(store.project.layers[0].transform.position == .zero)
        #expect(!store.undoManager.canUndo)
    }

    @Test func cancellingAContinuousChangeRestoresTheStart() throws {
        var a = shape("A")
        let store = makeStore(Project(layers: [a]))
        store.beginContinuousChange("Move")
        a.name = "Dragged"
        try store.updateContinuousChange(.updateLayers([a]))
        store.cancelContinuousChange()
        #expect(store.project.layers[0].name == "A")
        #expect(!store.undoManager.canUndo)
    }

    @Test func deletingAMaskClearsReferencesToIt() throws {
        let mask = shape("Mask")
        var masked = shape("Masked")
        masked.mask = MaskReference(layerID: mask.id)
        let store = makeStore(Project(layers: [mask, masked]))
        try store.perform(.deleteLayers([mask.id]))
        #expect(store.project.layers.count == 1)
        #expect(store.project.layers[0].mask == nil)
    }

    @Test func movingKeepsRelativeOrderAndRefusesCycles() throws {
        let a = shape("A"), b = shape("B"), c = shape("C")
        let group = Layer(name: "G", content: .group(GroupContent()), size: Size2(1, 1), position: .zero)
        let store = makeStore(Project(layers: [a, b, c, group]))

        // Asked for in reverse, moved in their existing order.
        try store.perform(.moveLayers([c.id, a.id], parentID: group.id, index: nil))
        #expect(store.project.layers.map(\.name) == ["B", "G"])
        #expect(store.project.layer(withID: group.id)?.children.map(\.name) == ["A", "C"])

        #expect(throws: EditorError.invalidMove) {
            try store.perform(.moveLayers([group.id], parentID: group.id, index: nil))
        }
    }

    @Test func compositionSettingsAreValidated() throws {
        let store = makeStore()
        var composition = store.project.composition
        composition.width = 0
        #expect(throws: EditorError.invalidValue) { try store.perform(.setComposition(composition)) }
        composition.width = 3840
        try store.perform(.setComposition(composition))
        #expect(store.project.composition.width == 3840)
        store.undoManager.undo()
        #expect(store.project.composition.width == 1920)
    }

    @Test func stepsWithTheSameKeyJoinUntilSomethingElseHappens() throws {
        let store = makeStore()
        let a = shape("A")
        try store.perform(.insertLayers([a], parentID: nil, index: nil))
        // Typing "Hi", a change from elsewhere, then "!" in the same session.
        try store.perform(.renameLayer(a.id, "H"), joining: "typing")
        try store.perform(.renameLayer(a.id, "Hi"), joining: "typing")
        try store.perform(.setLocked([a.id], true))
        try store.perform(.renameLayer(a.id, "Hi!"), joining: "typing")
        store.undoManager.undo()
        #expect(store.project.layers[0].name == "Hi" && store.project.layers[0].isLocked)
        store.undoManager.undo()
        #expect(store.project.layers[0].name == "Hi" && !store.project.layers[0].isLocked)
        store.undoManager.undo()
        #expect(store.project.layers[0].name == "A")
        // After an undo, the next step with the key starts afresh.
        try store.perform(.renameLayer(a.id, "B"), joining: "typing")
        store.undoManager.undo()
        #expect(store.project.layers[0].name == "A")
    }
}
