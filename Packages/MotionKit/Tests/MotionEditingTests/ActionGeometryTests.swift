import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

@Suite struct ActionGeometryTests {
    private let from = Vec2(100, 100)

    @Test func aMovesPathFollowsItsMode() {
        #expect(ActionGeometry.path(of: MoveAction(mode: .by, end: Vec2(50, 0)), from: from).end == Vec2(150, 100))
        #expect(ActionGeometry.path(of: MoveAction(mode: .to, end: Vec2(50, 0)), from: from).end == Vec2(50, 0))
        let p = ActionGeometry.path(of: MoveAction(mode: .by, initial: Vec2(0, 0), end: Vec2(10, 0)), from: from)
        #expect(p.start == .zero && p.end == Vec2(10, 0) && p.startHandle == nil)
    }

    @Test func draggingTheEndStoresWhatTheModeNeeds() {
        let by = ActionGeometry.settingEnd(MoveAction(mode: .by, end: .zero), to: Vec2(300, 50), from: from)
        #expect(by.end == Vec2(200, -50))
        let to = ActionGeometry.settingEnd(MoveAction(mode: .to, end: .zero), to: Vec2(300, 50), from: from)
        #expect(to.end == Vec2(300, 50))
    }

    @Test func draggingTheStartLeavesTheEndWhereItIs() {
        for mode in ActionMode.allCases {
            let move = MoveAction(mode: mode, end: mode == .by ? Vec2(100, 0) : Vec2(200, 100))
            let before = ActionGeometry.path(of: move, from: from).end
            let moved = ActionGeometry.settingStart(move, to: Vec2(0, 0), from: from)
            #expect(moved.initial == .zero)
            #expect(ActionGeometry.path(of: moved, from: from).end == before)
        }
    }

    @Test func curveHandlesAreOffsetsFromTheirEnds() {
        let move = MoveAction(mode: .by, end: Vec2(300, 0))
        let curved = ActionGeometry.settingHandle(move, first: true, to: Vec2(150, 0), from: from)
        #expect(curved.curve?.startHandle == Vec2(50, -100))
        let p = ActionGeometry.path(of: curved, from: from)
        #expect(p.startHandle == Vec2(150, 0))
        // The other handle kept its default, a third of the way back, lifted.
        #expect(p.endHandle == Vec2(300, 25))
    }

    @Test func aNewCurveArchesUpwardForAMoveToTheRight() {
        let c = ActionGeometry.defaultCurve(from: .zero, to: Vec2(300, 0))
        #expect(c.startHandle == Vec2(100, -75))
        #expect(c.endHandle == Vec2(-100, -75))
    }

    @Test func scaleAndRotateEndsFollowTheirModes() {
        let by = ActionGeometry.settingEnd(ScaleAction(mode: .by, end: .one), to: Vec2(1.5, 1), from: Vec2(0.5, 0.5))
        #expect(by.end == Vec2(3, 2))
        let spin = ActionGeometry.settingEnd(RotateAction(mode: .by, end: 0), to: 100, from: 30)
        #expect(spin.end == 70)
        #expect(ActionGeometry.settingEnd(RotateAction(mode: .to, end: 0), to: 100, from: 30).end == 100)
    }

    @Test func switchingModeKeepsTheMotion() {
        let layer = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), name: "S")
        var state = LayerState(design: layer)
        state.position = from
        state.scale = Vec2(2, 2)
        state.rotation = 45
        let move = Action(target: layer.id, start: 0, duration: 1, spec: .move(MoveAction(mode: .by, end: Vec2(10, 20))))
        guard case .move(let m) = ActionGeometry.switchingMode(move, to: .to, from: state).spec else { return }
        #expect(m.mode == .to && m.end == Vec2(110, 120))
        let scale = Action(target: layer.id, start: 0, duration: 1, spec: .scale(ScaleAction(mode: .to, end: Vec2(3, 1))))
        guard case .scale(let s) = ActionGeometry.switchingMode(scale, to: .by, from: state).spec else { return }
        #expect(s.mode == .by && s.end == Vec2(1.5, 0.5))
        let spin = Action(target: layer.id, start: 0, duration: 1, spec: .rotate(RotateAction(mode: .by, end: 90)))
        guard case .rotate(let r) = ActionGeometry.switchingMode(spin, to: .to, from: state).spec else { return }
        #expect(r.mode == .to && r.end == 135)
    }

    @Test func swappingEndsPlaysAResizeBackwards() throws {
        let layer = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 433, maxY: 1080), name: "S")
        let state = LayerState(design: layer)
        // An empty From starts from the layer's size, so that is where it now ends.
        let grow = Action(target: layer.id, start: 0, duration: 1, spec: .resize(ResizeAction(end: Size2(800, 600))))
        let back = try #require(ActionGeometry.swappingEnds(grow, from: state))
        guard case .resize(let r) = back.spec else { Issue.record("not a resize"); return }
        #expect(r.initial == Size2(800, 600) && r.end == Size2(433, 1080))
        // Swapped again, it runs forwards, from a From now set.
        guard case .resize(let again) = try #require(ActionGeometry.swappingEnds(back, from: state)).spec else { return }
        #expect(again.initial == Size2(433, 1080) && again.end == Size2(800, 600))
    }

    @Test func swappingEndsKeepsTheMode() throws {
        let layer = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), name: "S")
        var state = LayerState(design: layer)
        state.position = from
        state.scale = Vec2(2, 2)
        state.rotation = 45

        // A curved By move runs the same path the other way.
        let move = MoveAction(mode: .by, end: Vec2(300, 0), curve: MotionCurve(startHandle: Vec2(50, -100), endHandle: Vec2(-50, -100)))
        let before = ActionGeometry.path(of: move, from: from)
        let moving = Action(target: layer.id, start: 0, duration: 1, spec: .move(move))
        guard case .move(let m) = try #require(ActionGeometry.swappingEnds(moving, from: state)).spec else { return }
        let after = ActionGeometry.path(of: m, from: from)
        #expect(m.mode == .by && m.end == Vec2(-300, 0))
        #expect(after.start == before.end && after.end == before.start)
        #expect(after.startHandle == before.endHandle && after.endHandle == before.startHandle)

        let scale = Action(target: layer.id, start: 0, duration: 1, spec: .scale(ScaleAction(mode: .by, end: Vec2(1.5, 0.5))))
        guard case .scale(let s) = try #require(ActionGeometry.swappingEnds(scale, from: state)).spec else { return }
        #expect(s.mode == .by && s.initial == Vec2(3, 1) && s.end == Vec2(2.0 / 3, 2))

        let spin = Action(target: layer.id, start: 0, duration: 1, spec: .rotate(RotateAction(mode: .by, end: 90)))
        guard case .rotate(let r) = try #require(ActionGeometry.swappingEnds(spin, from: state)).spec else { return }
        #expect(r.mode == .by && r.initial == 135 && r.end == -90)

        let tilt = Action(target: layer.id, start: 0, duration: 1,
                          spec: .tilt(TiltAction(mode: .to, end: Tilt(x: 30, y: 0, depth: 800))))
        guard case .tilt(let t) = try #require(ActionGeometry.swappingEnds(tilt, from: state)).spec else { return }
        #expect(t.initial == Tilt(x: 30, y: 0, depth: 800) && t.end == Tilt(x: 0, y: 0, depth: 800))
    }

    @Test func swappingEndsSkipsWhatHasNoEnds() {
        let layer = LayerFactory.shape(.rectangle, in: Box(minX: 0, minY: 0, maxX: 10, maxY: 10), name: "S")
        let state = LayerState(design: layer)
        let show = Action(target: layer.id, start: 0, duration: 0, spec: .visibility(VisibilityAction(isVisible: true)))
        #expect(ActionGeometry.swappingEnds(show, from: state) == nil)
        // A rectangle has no star to start from.
        let star = Action(target: layer.id, start: 0, duration: 1,
                          spec: .star(StarAction(end: StarShape(points: 5, innerRadius: 0.5, cornerRadius: 0))))
        #expect(ActionGeometry.swappingEnds(star, from: state) == nil)
    }
}
