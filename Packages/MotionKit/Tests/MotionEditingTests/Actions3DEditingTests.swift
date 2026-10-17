import Foundation
import Testing
import MotionModel
import MotionEvaluation
@testable import MotionEditing

/// What Add Action offers in 3D, and the editing maths of Depth and Camera.
@Suite struct Actions3DEditingTests {
    private func card() -> Layer {
        Layer(name: "C", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                     fills: [Fill(paint: .color(.black))])),
              size: Size2(100, 80), position: Vec2(400, 300))
    }

    private func frame(_ children: [Layer], space: Space3D?) -> Layer {
        Layer(name: "F", content: .group(GroupContent(children: children, frame: FrameStyle(space: space))),
              size: Size2(800, 600), position: Vec2(400, 300))
    }

    @Test func depthIsOfferedOnlyInAFrameIn3D() {
        let inside = card(), outside = card()
        let deep = frame([inside], space: Space3D())
        let project = Project(composition: Composition(width: 800, height: 600), layers: [deep, outside])
        let kinds = ActionFactory.kinds(for: inside, in: project)
        #expect(kinds.contains(.depth))
        #expect(kinds.firstIndex(of: .depth) == kinds.firstIndex(of: .tilt).map { $0 + 1 })
        #expect(!ActionFactory.kinds(for: outside, in: project).contains(.depth))
        // The frame itself takes Camera; a flat one does not.
        #expect(ActionFactory.kinds(for: deep, in: project).contains(.camera))
        #expect(!ActionFactory.kinds(for: frame([], space: nil), in: project).contains(.camera))
        #expect(!ActionFactory.kinds(for: inside, in: project).contains(.camera))
    }

    @Test func newActionsDoSomethingVisible() {
        let deep = frame([], space: Space3D(distance: 1000))
        let camera = ActionFactory.make(.camera, for: deep, at: 0, state: LayerState(design: deep),
                                        frameRate: .fps60, rowOrder: 0)
        guard case .camera(let c) = camera.spec else { Issue.record("a camera"); return }
        #expect(c.end.distance == 500)
        let depth = ActionFactory.make(.depth, for: card(), at: 0, state: LayerState(design: card()),
                                       frameRate: .fps60, rowOrder: 0)
        #expect(depth.spec == .depth(DepthAction(mode: .by, end: 200)))
        #expect(camera.spec.kind.category == .space && ActionCategory.space.title == "3D")
    }

    @Test func depthSwapsAndSwitchesWithoutChangingItsMotion() throws {
        var state = LayerState(design: card())
        state.z = -100
        let by = Action(target: UUID(), start: 0, duration: 1, easing: .linear, spec: .depth(DepthAction(mode: .by, end: 300)))
        let swapped = try #require(ActionGeometry.swappingEnds(by, from: state))
        #expect(swapped.spec == .depth(DepthAction(mode: .by, initial: 200, end: -300)))
        let to = ActionGeometry.switchingMode(by, to: .to, from: state)
        #expect(to.spec == .depth(DepthAction(mode: .to, end: 200)))
        // A camera's ends trade places, an empty start read from the frame.
        let deep = frame([], space: Space3D(distance: 1000))
        let camera = Action(target: deep.id, start: 0, duration: 1, easing: .linear,
                            spec: .camera(CameraAction(end: Space3D(distance: 300))))
        let back = try #require(ActionGeometry.swappingEnds(camera, from: LayerState(design: deep)))
        #expect(back.spec == .camera(CameraAction(initial: Space3D(distance: 300), end: Space3D(distance: 1000))))
    }

    @Test func aDepthPastedOntoAnotherLayerMakesTheSameMove() {
        let to = Action(target: UUID(), start: 0, duration: 1, easing: .linear,
                        spec: .depth(DepthAction(mode: .to, initial: 0, end: 300)))
        let from = ActionOrigin(position: .zero, scale: .one, rotation: 0, size: Size2(10, 10), z: 0)
        let onto = ActionOrigin(position: .zero, scale: .one, rotation: 0, size: Size2(10, 10), z: -200)
        #expect(ActionEditing.carried(to, from: from, to: onto).spec == .depth(DepthAction(mode: .to, initial: -200, end: 100)))
    }
}
