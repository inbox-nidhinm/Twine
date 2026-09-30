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

    @Test func newActionsGoToTheBottomWhateverTheirLayer() {
        let other = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 5, maxY: 5), name: "O")
        let a = action(3, row: 0), b = action(0, row: 1, on: other)
        let project = Project(layers: [square, other], actions: [a, b])
        let added = ActionEditing.appendingRows([action(1)], in: project)
        #expect(added[0].rowOrder == 2)
        // The timeline is the order they were added, not their start times.
        var p = project
        p.actions += added
        #expect(ActionEditing.timeline(in: p).map(\.id) == [a.id, b.id, added[0].id])
    }

    @Test func aDuplicateGoesOnTheRowJustBelowItsOriginal() {
        let other = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 5, maxY: 5), name: "O")
        let a = action(0, row: 0), b = action(1, row: 1, on: other), c = action(2, row: 2)
        var project = Project(layers: [square, other], actions: [a, b, c])
        let (copies, moved) = ActionEditing.placingBelow(ActionEditing.duplicates(of: [b], rate: rate), originals: [b], in: project)
        #expect(copies.count == 1 && copies[0].targetLayerID == other.id)
        #expect(moved.map(\.id) == [c.id], "only the row under it moves down")
        for x in moved { project.actions[project.actions.firstIndex { $0.id == x.id }!] = x }
        project.actions += copies
        #expect(ActionEditing.timeline(in: project).map(\.id) == [a.id, b.id, copies[0].id, c.id])
    }

    @Test func rowsCanBeRearrangedAcrossLayers() {
        let other = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 5, maxY: 5), name: "O")
        let a = action(0, row: 0), b = action(1, row: 1, on: other), c = action(2, row: 2)
        var project = Project(layers: [square, other], actions: [a, b, c])
        let changed = ActionEditing.moving(c.id, toRow: 0, in: project)
        for x in changed { project.actions[project.actions.firstIndex { $0.id == x.id }!] = x }
        #expect(ActionEditing.timeline(in: project).map(\.id) == [c.id, a.id, b.id])
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

    @Test func severalTrimTogetherEachWithinItsOwnLimits() {
        let a = action(1, 1), b = action(0.5, 0.5)
        let hide = Action(target: square.id, start: 2, duration: 0, spec: .visibility(VisibilityAction(isVisible: false)))
        // Every end moves by the same time; an instant one has no end to move.
        let longer = ActionEditing.trimmed([a, b, hide], startEdge: false, by: 0.5, symmetric: false, rate: rate)
        #expect(longer.map(\.id) == [a.id, b.id])
        #expect(longer.map(\.end) == [2.5, 1.5])
        #expect(longer.map(\.start) == [1, 0.5])
        // Pulled earlier, the start stops at zero for the one that reaches it.
        let earlier = ActionEditing.trimmed([a, b], startEdge: true, by: -0.75, symmetric: false, rate: rate)
        #expect(earlier.map(\.start) == [0.25, 0])
        #expect(earlier.map(\.end) == [2, 1])
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

    @Test func aMovePastedOntoAnotherLayerMakesTheSameMotionFromItsOwnPlace() throws {
        // The square's centre is at (5, 5); the other layer's at (100, 200).
        let other = LayerFactory.shape(.rectangle, in: Box(minX: 90, minY: 190, maxX: 110, maxY: 210), name: "O")
        let project = Project(layers: [square, other])
        var move = Action(target: square.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .to, initial: Vec2(0, 5), end: Vec2(45, 5))))
        move.motionBlur = 0.5
        let origin = ActionOrigin(ActionTracks([move]).inheritedState(for: move, of: square))
        let pasted = ActionEditing.pasted([move], onto: [other], at: 2, in: project, rate: rate, origins: [move.id: origin])
        guard case .move(let m) = try #require(pasted.first).spec else { Issue.record("not a move"); return }
        // From 5 to the left of it, to 40 to the right, as on the square.
        #expect(m.initial == Vec2(95, 200) && m.end == Vec2(140, 200) && m.mode == .to)
        #expect(pasted.first?.start == 2 && pasted.first?.duration == 1 && pasted.first?.motionBlur == 0.5)
        // Back on its own layer, it is copied exactly.
        let back = ActionEditing.pasted([move], onto: [square], at: 2, in: project, rate: rate, origins: [move.id: origin])
        #expect(back.first?.spec == move.spec)
        // By values are the same motion wherever they go.
        let by = Action(target: square.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .by, end: Vec2(10, 0))))
        let byOrigin = ActionOrigin(ActionTracks([by]).inheritedState(for: by, of: square))
        #expect(ActionEditing.pasted([by], onto: [other], at: 0, in: project, rate: rate, origins: [by.id: byOrigin]).first?.spec == by.spec)
    }

    @Test func scalesTurnsAndSizesCarryByRatioAndDifference() {
        let from = ActionOrigin(position: .zero, scale: Vec2(1, 1), rotation: 10, size: Size2(100, 50))
        let to = ActionOrigin(position: .zero, scale: Vec2(2, 2), rotation: 40, size: Size2(200, 200))
        func carried(_ spec: ActionSpec) -> ActionSpec {
            ActionEditing.carried(Action(target: square.id, start: 0, duration: 1, spec: spec), from: from, to: to).spec
        }
        #expect(carried(.scale(ScaleAction(mode: .to, end: Vec2(1.5, 1.5)))) == .scale(ScaleAction(mode: .to, end: Vec2(3, 3))))
        #expect(carried(.rotate(RotateAction(mode: .to, initial: 0, end: 90))) == .rotate(RotateAction(mode: .to, initial: 30, end: 120)))
        #expect(carried(.resize(ResizeAction(end: Size2(150, 25)))) == .resize(ResizeAction(end: Size2(300, 100))))
        // Nothing else changes.
        #expect(carried(.opacity(OpacityAction(end: 0.2))) == .opacity(OpacityAction(end: 0.2)))
    }

    @Test func pastedActionsJoinTheirLayersRows() {
        let other = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 5, maxY: 5), name: "O")
        let lone = LayerFactory.shape(.ellipse, in: Box(minX: 0, minY: 0, maxX: 5, maxY: 5), name: "L")
        let a = action(0, row: 0), b = action(0, row: 1, on: other), c = action(0, row: 2)
        let project = Project(layers: [square, other, lone], actions: [a, b, c])
        let onOther = action(1, on: other), onLone = action(1, on: lone)
        let placed = ActionEditing.placingWithTheirLayers([onOther, onLone], in: project)
        var p = project
        p.actions = project.actions.map { old in placed.moved.first { $0.id == old.id } ?? old } + placed.actions
        // Just under the other layer's row; one for a layer with none goes last.
        #expect(ActionEditing.timeline(in: p).map(\.id) == [a.id, b.id, onOther.id, c.id, onLone.id])
        #expect(placed.moved.map(\.id) == [c.id])
    }

    @Test func textAndSoundPresetsOnlyPasteWhereTheyFit() {
        let text = Layer(name: "T", content: .text(TextContent(text: "abc")), size: Size2(40, 20), position: .zero)
        let project = Project(layers: [square, text])
        var letters = PresetRecipe.defaults(.slideIn)
        letters.unit = .letters
        let bar = Action(target: text.id, start: 0, duration: 1, spec: .preset(letters))
        #expect(ActionEditing.pasted([bar], onto: [square], at: 0, in: project, rate: rate).isEmpty)
        #expect(ActionEditing.pasted([bar], onto: [text], at: 0, in: project, rate: rate).count == 1)
        let fade = Action(target: square.id, start: 0, duration: 1, spec: .preset(PresetRecipe.defaults(.fadeSoundIn)))
        #expect(ActionEditing.pasted([fade], onto: [square], at: 0, in: project, rate: rate).isEmpty)
        // An ordinary preset goes onto any layer that draws, Out as well as In.
        let out = Action(target: text.id, start: 0, duration: 1, spec: .preset(PresetRecipe.defaults(.slideOut)))
        #expect(ActionEditing.pasted([out], onto: [square], at: 0, in: project, rate: rate).count == 1)
    }

    @Test func pastedRowsGoToTheBottom() {
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
