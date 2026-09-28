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
    private func makeStore(_ project: Project = Project()) -> ProjectStore {
        let undo = UndoManager()
        undo.groupsByEvent = false
        return ProjectStore(project: project, undoManager: undo)
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
}
