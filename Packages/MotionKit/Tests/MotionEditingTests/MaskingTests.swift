import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

/// Masks as Figma has them, and older projects' masks made into them
/// (4 October 2026).
@Suite struct MaskingTests {
    private func box(_ name: String, _ x: Double, _ y: Double, _ size: Double = 20) -> Layer {
        Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero))), size: Size2(size, size),
              position: Vec2(x, y))
    }

    @Test func oneLayerBecomesAMaskWhereItIs() throws {
        let a = box("A", 10, 10), b = box("B", 10, 10)
        var project = Project(layers: [a, b])
        try Masking.useAsMask([a.id], in: project).apply(to: &project)
        #expect(project.layers.map(\.id) == [a.id, b.id] && project.layers[0].isMask)
    }

    @Test func severalGoIntoAMaskGroupWithTheBackOneTheMask() throws {
        let behind = box("Behind", 0, 0), a = box("A", 10, 10), b = box("B", 30, 30), front = box("Front", 0, 0)
        var project = Project(layers: [behind, a, b, front])
        try Masking.useAsMask([b.id, a.id], in: project).apply(to: &project)
        #expect(project.layers.count == 3 && project.layers[0].id == behind.id && project.layers[2].id == front.id)
        let group = project.layers[1]
        #expect(group.name == "Mask group" && group.children.map(\.id) == [a.id, b.id])
        #expect(group.children[0].isMask && !group.children[1].isMask)
        // Nothing moved on screen.
        let scene = evaluateDesign(project)
        #expect(scene.bounds(of: b.id) == Box(minX: 20, minY: 20, maxX: 40, maxY: 40))
        #expect(scene.layer(b.id)?.mask?.layerID == a.id && scene.layer(front.id)?.mask == nil)
    }

    @Test func aGroupCannotBeTheMask() {
        let inner = box("Inner", 0, 0)
        let group = Layer(name: "G", content: .group(GroupContent(children: [inner])), size: Size2(20, 20), position: .zero)
        let a = box("A", 0, 0)
        let project = Project(layers: [group, a])
        #expect(throws: Masking.Refusal.cannotMask(group.id)) { try Masking.useAsMask([group.id, a.id], in: project) }
        #expect(throws: Masking.Refusal.apart) { try Masking.useAsMask([inner.id, a.id], in: project) }
    }

    @Test func removingAMaskKeepsItsGroup() throws {
        let a = box("A", 0, 0), b = box("B", 0, 0)
        var project = Project(layers: [a, b])
        try Masking.useAsMask([a.id, b.id], in: project).apply(to: &project)
        try Masking.removeMask(a.id, in: project).apply(to: &project)
        #expect(project.layers.count == 1 && project.layers[0].children.map(\.isMask) == [false, false])
    }

    @MainActor @Test func useAsMaskIsOneUndoStep() throws {
        let a = box("A", 0, 0), b = box("B", 0, 0)
        let undo = UndoManager()
        let store = ProjectStore(project: Project(layers: [a, b]), undoManager: undo)
        try store.perform(Masking.useAsMask([a.id, b.id], in: store.project))
        undo.undo()
        #expect(store.project.layers.map(\.id) == [a.id, b.id] && !store.project.layers[0].isMask)
    }

    // MARK: Older projects

    @Test func anOldMaskBecomesAMaskGroup() throws {
        let mask = box("Mask", 10, 10), other = box("Other", 0, 0)
        var masked = box("Masked", 10, 10, 40)
        masked.legacyMask = MaskReference(layerID: mask.id, isInverted: true)
        let slide = Action(target: mask.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .by, end: Vec2(5, 0))))
        let before = Project(layers: [mask, other, masked], actions: [slide])
        let after = MaskConversion.converted(before)
        #expect(!after.hasLegacyMasks)
        let ids = after.layers.map(\.id)
        #expect(ids.count == 2 && ids[0] == other.id)
        let group = after.layers[1]
        #expect(group.name == "Mask group" && group.children.map(\.id) == [mask.id, masked.id] && group.children[0].isMask)
        // The same on screen, and the mask's action came along.
        #expect(evaluateDesign(after).bounds(of: masked.id) == evaluateDesign(before).bounds(of: masked.id))
        #expect(evaluateDesign(after).layer(masked.id)?.mask?.layerID == mask.id)
        #expect(after.actions.map(\.targetLayerID) == [mask.id])
    }

    @Test func anOldMaskOverLayersInTwoPlacesIsCopied() throws {
        let mask = box("Mask", 10, 10)
        var top = box("Top", 10, 10), inside = box("Inside", 10, 10)
        top.legacyMask = MaskReference(layerID: mask.id)
        inside.legacyMask = MaskReference(layerID: mask.id)
        var holder = Layer(name: "Holder", content: .group(GroupContent(children: [inside])), size: Size2(20, 20),
                           position: Vec2(50, 50))
        holder.transform.anchor = .zero
        let slide = Action(target: mask.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .by, end: Vec2(5, 0))))
        let after = MaskConversion.converted(Project(layers: [mask, top, holder], actions: [slide]))
        var masks: [Layer] = []
        after.forEachLayer { if $0.isMask { masks.append($0) } }
        #expect(masks.count == 2 && Set(masks.map(\.id)).contains(mask.id))
        #expect(after.actions.count == 2, "the copy has the mask's action")
        let scene = evaluateDesign(after)
        #expect(scene.layer(top.id)?.mask != nil && scene.layer(inside.id)?.mask != nil)
        // The copy sits where the mask did, carried into the group's space.
        let copy = try #require(masks.first { $0.id != mask.id })
        #expect(scene.bounds(of: copy.id) == Box(minX: 0, minY: 0, maxX: 20, maxY: 20))
    }

    @Test func openingAnOldFileReadsItsMasks() throws {
        let mask = box("Mask", 10, 10)
        var masked = box("Masked", 10, 10)
        masked.legacyMask = MaskReference(layerID: mask.id)
        // As an older Twine wrote it: the masked layer names its mask.
        var json = String(decoding: try ProjectFormat.encode(Project(layers: [mask, masked])), as: UTF8.self)
        json = json.replacingOccurrences(of: "\"formatVersion\" : 5", with: "\"formatVersion\" : 4")
        json = json.replacingOccurrences(of: "\"name\" : \"Masked\",", with: "\"mask\" : { \"isInverted\" : false, \"layerID\" : \"\(mask.id.uuidString)\" }, \"name\" : \"Masked\",")
        let read = try ProjectFormat.decode(Data(json.utf8))
        #expect(read.layers[1].legacyMask?.layerID == mask.id)
        // Written again, it is not kept.
        #expect(!String(decoding: try ProjectFormat.encode(read), as: UTF8.self).contains("layerID"))
        #expect(MaskConversion.converted(read).layers.first?.children.first?.isMask == true)
    }
}
