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

    @Test func depthIsOfferedWhereverMoveIs() {
        let inside = card(), outside = card()
        let deep = frame([inside], space: Space3D())
        let project = Project(composition: Composition(width: 800, height: 600), layers: [deep, outside])
        let kinds = ActionFactory.kinds(for: inside, in: project)
        #expect(kinds.contains(.depth))
        #expect(kinds.firstIndex(of: .depth) == kinds.firstIndex(of: .tilt).map { $0 + 1 })
        // Outside a 3D frame too, seen from its own tilt's depth.
        #expect(ActionFactory.kinds(for: outside, in: project).contains(.depth))
        let sound = Layer(name: "A", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)
        #expect(!ActionFactory.kinds(for: sound, in: project).contains(.depth))
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

/// The 3D group of presets.
@Suite struct Presets3DTests {
    private func card() -> Layer {
        Layer(name: "C", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                     fills: [Fill(paint: .color(.black))])),
              size: Size2(100, 80), position: Vec2(400, 300))
    }

    private func run(_ kind: PresetKind, on layer: Layer) -> (ActionTracks, Action) {
        let action = Presets.action(Presets.preset(kind), for: layer, at: 1, frameRate: .fps60)
        return (ActionTracks([action]), action)
    }

    @Test func theyAreOneGroupOfPairs() {
        let group = Presets.library.filter { $0.group == .space }.map(\.name)
        #expect(group == ["Flip", "Swing", "Fold", "Tumble", "Fly", "Iso Lift", "Spin 3D", "Float"])
        #expect(PresetGroup.space.title == "3D")
        #expect(Presets.name(of: .flyOut) == "Fly Out" && Presets.name(of: .spin3D) == "Spin 3D")
        // Every one suits a plain layer, inside a 3D frame or not.
        let layer = card()
        let offered = Presets.available(for: [layer], in: Project(layers: [layer])).map(\.kind)
        for kind in [PresetKind.flipIn, .swingIn, .foldIn, .tumbleIn, .flyIn, .isoLiftIn, .spin3D, .float] {
            #expect(offered.contains(kind), "\(kind)")
        }
    }

    @Test func entrancesStartAwayAndLandWhereTheLayerWas() {
        let layer = card()
        for kind in [PresetKind.flipIn, .swingIn, .foldIn, .tumbleIn, .flyIn, .isoLiftIn] {
            let (tracks, action) = run(kind, on: layer)
            let before = tracks.state(of: layer, at: 0), after = tracks.state(of: layer, at: action.end + 0.01)
            #expect(before.tilt != .none || before.z != 0 || before.bend != .zero, "\(kind) starts turned, away or bent")
            #expect(after.tilt.x == 0 && after.tilt.y == 0 && after.z == 0 && after.bend == .zero, "\(kind) lands")
            #expect(after.position == Vec2(400, 300) && after.rotation == 0, "\(kind)")
        }
        let (fly, _) = run(.flyIn, on: layer)
        #expect(fly.state(of: layer, at: 0).z == -1200)
        let (flip, _) = run(.flipIn, on: layer)
        #expect(flip.state(of: layer, at: 0).tilt.x == -90)
        let (fold, _) = run(.foldIn, on: layer)
        #expect(fold.state(of: layer, at: 0).bend == Vec2(180, 0))
    }

    @Test func exitsGoAndTheEmphasesComeBack() {
        let layer = card()
        let (fly, action) = run(.flyOut, on: layer)
        #expect(fly.state(of: layer, at: action.end).z == 600)
        let (spin, s) = run(.spin3D, on: layer)
        let half = spin.state(of: layer, at: s.start + s.duration / 2).tilt.y
        #expect(half < -10 && half > -350)
        #expect(abs(spin.state(of: layer, at: s.end).tilt.y + 360) < 1e-9)
        let (float, f) = run(.float, on: layer)
        #expect(float.state(of: layer, at: f.start + f.duration / 2).z == 60)
        #expect(abs(float.state(of: layer, at: f.end).z) < 1e-9)
    }

    @Test func flyingInSeesTheLayerSmallThenWhole() throws {
        let layer = card()
        let (_, action) = run(.flyIn, on: layer)
        let project = Project(layers: [layer], actions: [action])
        func width(at t: Double) throws -> Double {
            let p = try #require(evaluate(project, at: t).layer(layer.id)).projection
            return p.apply(Vec2(100, 40))!.x - p.apply(Vec2(0, 40))!.x
        }
        // Twice its tilt's depth away: half its size.
        #expect(abs(try width(at: 0) - 50) < 1e-9)
        #expect(abs(try width(at: action.end + 0.01) - 100) < 1e-9)
    }

    @Test func lettersFlyInOneByOne() throws {
        var text = LayerFactory.text(at: Vec2(400, 300), name: "T")
        if case .text(var t) = text.content {
            t.text = "Hello"
            text.content = .text(t)
        }
        var action = Presets.action(Presets.preset(.flyIn), for: text, at: 0, frameRate: .fps60)
        guard case .preset(var p) = action.spec else { Issue.record("a preset"); return }
        p.unit = .letters
        action.spec = .preset(p)
        let scene = evaluate(Project(layers: [text], actions: [action]), at: action.duration * 0.2)
        guard case .text(let resolved) = try #require(scene.layer(text.id)).content else { Issue.record("text"); return }
        #expect(!resolved.units.isEmpty)
        // The first letter is on its way in, far off and so drawn small.
        let first = try #require(resolved.units.first)
        #expect(abs(first.transform.w - 1) > 1e-3)
    }

    @Test func theySplitIntoTheActionsTheyAreMadeOf() throws {
        let layer = card()
        for kind in [PresetKind.tumbleIn, .foldOut, .float] {
            let (tracks, action) = run(kind, on: layer)
            let parts = try #require(Presets.split(action, of: layer, from: tracks.inheritedState(for: action, of: layer),
                                                   frameRate: .fps60))
            let kinds = Set(parts.map(\.spec.kind))
            #expect(kinds.contains(.tilt) || kinds.contains(.bend), "\(kind)")
        }
        // A fold bends one picture, so it never goes letter by letter.
        #expect(PresetKind.foldIn.movesWholeLayer)
    }
}
