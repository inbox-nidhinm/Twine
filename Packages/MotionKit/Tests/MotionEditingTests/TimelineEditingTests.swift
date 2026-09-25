import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct TimelineEditingTests {
    private let square = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), name: "S")
    private let rate = FrameRate.fps60

    private func action(_ start: Double, _ duration: Double = 0.5, row: Int = 0, on layer: Layer? = nil) -> Action {
        Action(target: (layer ?? square).id, start: start, duration: duration, rowOrder: row,
               spec: .opacity(OpacityAction(end: 0)))
    }

    @Test func newActionsSlotInByStartTime() {
        let a = action(0, row: 0), b = action(2, row: 1)
        let project = Project(layers: [square], actions: [a, b])
        let (new, changed) = ActionEditing.slotting(action(1), into: project)
        #expect(new.rowOrder == 1)
        #expect(changed.map(\.id) == [b.id])
        #expect(changed[0].rowOrder == 2)
    }

    @Test func rowsCanBeRearranged() {
        let a = action(0, row: 0), b = action(1, row: 1), c = action(2, row: 2)
        var project = Project(layers: [square], actions: [a, b, c])
        let changed = ActionEditing.moving(c.id, toRow: 0, in: project)
        for x in changed { project.actions[project.actions.firstIndex { $0.id == x.id }!] = x }
        #expect(ActionEditing.rows(on: square.id, in: project).map(\.id) == [c.id, a.id, b.id])
    }

    @Test func movingKeepsSpacingLandsOnFramesAndStopsAtZero() {
        let moved = ActionEditing.moved([action(1), action(2)], by: 0.504, rate: rate)
        #expect(moved.map(\.start) == [1.5, 2.5])
        let early = ActionEditing.moved([action(1), action(2)], by: -5, rate: rate)
        #expect(early.map(\.start) == [0, 1])
    }

    @Test func trimmingOneEndKeepsTheOther() {
        let a = action(1, 1)
        let start = ActionEditing.trimmed(a, startEdge: true, to: 1.5, symmetric: false, rate: rate)
        #expect(start.start == 1.5 && start.end == 2)
        let end = ActionEditing.trimmed(a, startEdge: false, to: 3, symmetric: false, rate: rate)
        #expect(end.start == 1 && end.end == 3)
    }

    @Test func trimmingNeverGoesBelowAFrameOrBeforeZero() {
        let a = action(1, 1)
        let squashed = ActionEditing.trimmed(a, startEdge: true, to: 5, symmetric: false, rate: rate)
        #expect(abs(squashed.duration - rate.frameDuration) < 1e-9)
        let early = ActionEditing.trimmed(a, startEdge: true, to: -3, symmetric: false, rate: rate)
        #expect(early.start == 0 && early.end == 2)
    }

    @Test func optionTrimsBothEndsAroundTheMiddle() {
        let a = action(1, 1)
        let wider = ActionEditing.trimmed(a, startEdge: false, to: 2.5, symmetric: true, rate: rate)
        #expect(wider.start == 0.5 && wider.end == 2.5)
        let narrower = ActionEditing.trimmed(a, startEdge: true, to: 1.25, symmetric: true, rate: rate)
        #expect(narrower.start == 1.25 && narrower.end == 1.75)
    }

    @Test func staggerSpacesStartsEvenly() {
        let s = ActionEditing.staggered([action(2), action(0), action(5)], gap: 0.25, rate: rate)
        #expect(s.map(\.start) == [2, 2.25, 2.5])
    }

    @Test func duplicatesCarryOnAfterTheOriginals() {
        let a = action(1, 0.5), b = action(1.5, 1)
        let copies = ActionEditing.duplicates(of: [a, b], rate: rate)
        #expect(copies.map(\.start) == [2.5, 3])
        #expect(Set(copies.map(\.id)).isDisjoint(with: [a.id, b.id]))
    }

    @Test func pastingLandsAtThePlayheadOnTheSelectedLayers() {
        let other = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 5, maxY: 5), name: "O")
        let group = LayerFactory.group(in: Box(minX: 0, minY: 0, maxX: 1, maxY: 1), children: [], name: "G")
        let project = Project(layers: [square, other, group])
        let clip = [action(1), action(1.5)]
        let onOther = ActionEditing.pasted(clip, onto: [other], at: 3, in: project, rate: rate)
        #expect(onOther.map(\.start) == [3, 3.5])
        #expect(onOther.allSatisfy { $0.targetLayerID == other.id })
        let back = ActionEditing.pasted(clip, onto: [], at: 0, in: project, rate: rate)
        #expect(back.allSatisfy { $0.targetLayerID == square.id })
        // A group cannot resize, so a pasted Resize skips it.
        let resize = Action(target: square.id, start: 0, duration: 1, spec: .resize(ResizeAction(end: Size2(1, 1))))
        #expect(ActionEditing.pasted([resize], onto: [group], at: 0, in: project, rate: rate).isEmpty)
    }

    @Test func pastedRowsGoAfterTheLayersOwn() {
        let project = Project(layers: [square], actions: [action(0, row: 4)])
        let rows = ActionEditing.appendingRows([action(1), action(2)], in: project)
        #expect(rows.map(\.rowOrder) == [5, 6])
    }

    @Test func edgesForJumpingThePlayhead() {
        let project = Project(layers: [square], actions: [action(1, 0.5), action(3, 0)])
        #expect(ActionEditing.edges(in: project) == [1, 1.5, 3])
        #expect(ActionEditing.edge(after: 1, in: project) == 1.5)
        #expect(ActionEditing.edge(before: 1, in: project) == nil)
        #expect(ActionEditing.edge(before: 2, in: project) == 1.5)
    }
}
