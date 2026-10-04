import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct AnimateEditingTests {
    private func square() -> Layer {
        Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [])),
              size: Size2(100, 100), position: Vec2(100, 100))
    }

    private func shown(_ layer: Layer, _ actions: [Action], at time: Double) -> ResolvedLayer {
        evaluate(Project(layers: [layer], actions: actions), at: time).layers[0]
    }

    @Test func aResizeAtThePlayheadShowsThereThroughAMoveBy() throws {
        let layer = square()
        let move = Action(target: layer.id, start: 0, duration: 1, easing: .linear, spec: .move(MoveAction(mode: .by, end: Vec2(50, 0))))
        let before = AnimateEditing.shown(layer, as: shown(layer, [move], at: 2))
        #expect(before.transform.position == Vec2(150, 100))
        // The right edge dragged 50 px out: half as wide again, the centre 25 px on.
        var edited = before
        edited.size = Size2(150, 100)
        edited.transform.anchor = Vec2(75, 50)
        edited.transform.position = Vec2(175, 100)
        let design = AnimateEditing.designed(layer, shown: before, edited: edited)
        #expect(design.transform.position == Vec2(125, 100) && design.size == Size2(150, 100))
        let after = shown(design, [move], at: 2)
        #expect(after.position == Vec2(175, 100) && after.size == Size2(150, 100))
    }

    @Test func aResizeToFollowsAResizeOfTheLayer() throws {
        let layer = square()
        let resize = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                            spec: .resize(ResizeAction(end: Size2(200, 200), isLinked: true)))
        let before = AnimateEditing.shown(layer, as: shown(layer, [resize], at: 2))
        #expect(before.size == Size2(200, 200))
        var edited = before
        edited.size = Size2(300, 300)
        edited.transform.anchor = Vec2(150, 150)
        let design = AnimateEditing.designed(layer, shown: before, edited: edited)
        #expect(design.size == Size2(150, 150))
        let carried = AnimateEditing.following([resize], from: layer, to: design)
        guard case .resize(let r)? = carried.first?.spec else { Issue.record("not carried"); return }
        #expect(r.end == Size2(300, 300))
        #expect(shown(design, carried, at: 2).size == Size2(300, 300))
    }

    @Test func aTurnCarriesRotateToAndStartingValuesButNotBy() {
        let layer = square()
        var turned = layer
        turned.transform.rotation = 30
        let to = Action(target: layer.id, start: 0, duration: 1, spec: .rotate(RotateAction(mode: .to, initial: 10, end: 90)))
        let by = Action(target: layer.id, start: 2, duration: 1, spec: .rotate(RotateAction(mode: .by, end: 45)))
        let opacity = Action(target: layer.id, start: 0, duration: 1, spec: .opacity(OpacityAction(end: 0)))
        let carried = AnimateEditing.following([to, by, opacity], from: layer, to: turned)
        #expect(carried.count == 1)
        guard case .rotate(let r)? = carried.first?.spec else { Issue.record("not carried"); return }
        #expect(r.end == 120 && r.initial == 40)
    }

    @Test func aGroupsScaleToFollowsItsScale() {
        var group = LayerFactory.group(in: Box(origin: .zero, size: Size2(10, 10)), children: [], name: "G")
        let scale = Action(target: group.id, start: 0, duration: 1, spec: .scale(ScaleAction(mode: .to, end: Vec2(2, 2))))
        let old = group
        group.transform.scale = Vec2(1.5, 1.5)
        guard case .scale(let s)? = AnimateEditing.following([scale], from: old, to: group).first?.spec else {
            Issue.record("not carried"); return
        }
        #expect(s.end == Vec2(3, 3))
    }

    @Test func aLayerDrawnIntoAMovingFrameLandsWhereItWasDrawn() {
        // The frame has slid 100 px right by the playhead: drawn at (150, 50)
        // in the composition, the shape sits at (50, 50) in the frame.
        let made = Layer(name: "R", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [])),
                         size: Size2(10, 10), position: Vec2(150, 50))
        let placed = Arrangement.placed(made, into: UUID(), parentWorld: .translation(Vec2(100, 0)))
        #expect(placed.transform.position == Vec2(50, 50))
    }
}
