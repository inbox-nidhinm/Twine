import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

private func box(_ name: String, _ x: Double, _ y: Double, _ w: Double = 20, _ h: Double = 20) -> Layer {
    LayerFactory.shape(.rectangle, in: Box(minX: x, minY: y, maxX: x + w, maxY: y + h), name: name)
}

private func corners(_ project: Project, _ id: UUID, at time: Double = 0) -> [Vec2] {
    evaluate(project, at: time).worldCorners(of: id) ?? []
}

private func close(_ a: [Vec2], _ b: [Vec2]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { abs($0.x - $1.x) < 1e-6 && abs($0.y - $1.y) < 1e-6 }
}

@Suite struct CopyAndMaskTests {
    @Test func aCopyKeepsEverythingButItsIDs() {
        var layer = box("A", 0, 0)
        layer.blendMode = .multiply
        layer.keepsProportions = true
        layer.transform.skew = Vec2(10, 0)
        let copy = layer.duplicated()
        #expect(copy.id != layer.id)
        #expect(copy.blendMode == .multiply && copy.keepsProportions && copy.transform.skew == Vec2(10, 0))
        #expect(copy.look?.fills.first?.id != layer.look?.fills.first?.id)
    }

    @Test func aLayerAndItsMaskCopiedTogetherPairUp() {
        let m = box("M", 0, 0)
        var a = box("A", 0, 0)
        a.mask = MaskReference(layerID: m.id)
        // Copied one by one, as Duplicate and Paste do with a selection.
        var map: [UUID: UUID] = [:]
        let copies = [a, m].map { $0.duplicated(recordingIDs: &map) }.map { $0.remappingMasks(map) }
        #expect(copies[0].mask?.layerID == copies[1].id)
    }

    @Test func aMaskNamingALayerThatIsNotThereGoes() throws {
        var a = box("A", 0, 0)
        a.mask = MaskReference(layerID: UUID())
        var project = Project()
        try EditorCommand.insertLayers([a], parentID: nil, index: nil).apply(to: &project)
        #expect(project.layers[0].mask == nil)
    }

    @Test func ungroupingKeepsMasksThatNameAChild() throws {
        let child = box("Child", 0, 0)
        var outside = box("Outside", 50, 50)
        outside.mask = MaskReference(layerID: child.id)
        var project = Project(layers: [outside, child])
        let (grouping, groupID) = try Arrangement.group([child.id], in: project, name: "G")
        try grouping.apply(to: &project)
        #expect(project.layer(withID: outside.id)?.mask?.layerID == child.id)
        try Arrangement.ungroup(groupID, in: project).0.apply(to: &project)
        #expect(project.layer(withID: outside.id)?.mask?.layerID == child.id)
    }

    /// A turned and slanted layer, with a Rotate, in a flipped group that is
    /// turned and scaled too.
    private func flipped() throws -> (Project, groupID: UUID, childID: UUID) {
        var child = box("Child", 40, 10, 30, 12)
        child.transform.rotation = 30
        child.transform.skew = Vec2(12, 0)
        var project = Project(layers: [child, box("Other", 0, 0)])
        let (grouping, groupID) = try Arrangement.group([child.id, project.layers[1].id], in: project, name: "G")
        try grouping.apply(to: &project)
        _ = project.updateLayer(groupID) {
            $0.transform.scale = Vec2(-1.5, 1.5)
            $0.transform.rotation = 20
        }
        project.actions = [Action(target: child.id, start: 0, duration: 1, spec: .rotate(RotateAction(mode: .to, end: 75)))]
        return (project, groupID, child.id)
    }

    @Test func ungroupingAFlippedGroupKeepsItsChildrenInPlace() throws {
        var (project, groupID, childID) = try flipped()
        let still = corners(project, childID), moved = corners(project, childID, at: 1)
        try Arrangement.ungroup(groupID, in: project).0.apply(to: &project)
        #expect(close(corners(project, childID), still))
        #expect(close(corners(project, childID, at: 1), moved))
    }

    @Test func movingOutOfAFlippedGroupKeepsTheLayerInPlace() throws {
        var (project, _, childID) = try flipped()
        let still = corners(project, childID), moved = corners(project, childID, at: 1)
        try Arrangement.move([childID], to: nil, index: nil, in: project).apply(to: &project)
        #expect(project.location(of: childID)?.parentID == nil)
        #expect(close(corners(project, childID), still))
        #expect(close(corners(project, childID, at: 1), moved))
    }
}

@Suite struct WildTimeTests {
    @Test func timesPastADayAreRefused() throws {
        var project = Project(layers: [box("A", 0, 0)])
        var long = project.composition
        long.duration = 1e20
        #expect(throws: EditorError.invalidValue) { try EditorCommand.setComposition(long).apply(to: &project) }
        let far = Action(target: project.layers[0].id, start: 1e20, duration: 1, spec: .opacity(OpacityAction(end: 0)))
        #expect(throws: EditorError.invalidValue) { try EditorCommand.insertActions([far]).apply(to: &project) }
    }

    @Test func frameNumbersNeverOverflow() {
        let rate = FrameRate.fps60
        #expect(rate.frame(at: 1e300) > 0 && rate.frame(at: .nan) == 0)
        #expect(rate.snapped(-1e300).isFinite)
    }

    @Test func aDamagedFrameRateReadsAsThirty() throws {
        let rate = try JSONDecoder().decode(FrameRate.self, from: Data(#"{"frames": 0, "seconds": 1}"#.utf8))
        #expect(rate == .fps30)
        let fine = try JSONDecoder().decode(FrameRate.self, from: Data(#"{"frames": 30000, "seconds": 1001}"#.utf8))
        #expect(fine == .fps29_97)
    }
}
