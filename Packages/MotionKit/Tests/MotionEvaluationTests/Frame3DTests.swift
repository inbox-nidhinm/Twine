import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// Frames in 3D: their children placed in one space, seen through one
/// camera, as `evaluate` resolves them.
@Suite struct Frame3DTests {
    static func card(_ name: String, at position: Vec2, z: Double = 0, tilt: Tilt = .none) -> Layer {
        var layer = Layer(name: name, content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                  fills: [Fill(paint: .color(.black))])),
                          size: Size2(100, 80), position: position)
        layer.transform.z = z
        layer.transform.tilt = tilt
        return layer
    }

    static func frame(_ children: [Layer], space: Space3D? = Space3D(distance: 1000)) -> Layer {
        Layer(name: "F", content: .group(GroupContent(children: children, frame: FrameStyle(space: space))),
              size: Size2(800, 600), position: Vec2(400, 300))
    }

    static func scene(_ layers: [Layer], actions: [Action] = [], at time: Double = 0, cache: EvaluationCache? = nil) -> ResolvedScene {
        evaluate(Project(composition: Composition(width: 800, height: 600), layers: layers, actions: actions),
                 at: time, cache: cache)
    }

    private func close(_ a: Vec2?, _ b: Vec2?, _ tolerance: Double = 1e-6) -> Bool {
        guard let a, let b else { return false }
        return abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func childrenOfAFrameIn3DAreSeenThroughItsCamera() throws {
        let near = Self.card("Near", at: Vec2(400, 300), z: 200)
        let s = Self.scene([Self.frame([near])])
        let placed = try #require(s.layer(near.id))
        let camera = Camera3D(distance: 1000, vanishingPoint: Vec2(400, 300))
        let pose = Pose3D.layer(position: Vec2(400, 300), z: 200, anchor: Vec2(50, 40))
        #expect(placed.projection == camera.projection(of: pose))
        #expect(placed.placed.depth == 200)
        // 200 nearer from 1000 away: a quarter larger.
        let w = placed.projection.apply(Vec2(100, 40))!.x - placed.projection.apply(Vec2(0, 40))!.x
        #expect(abs(w - 125) < 1e-9)
        // The frame itself is flat in its parent.
        #expect(s.layer(s.layers[0].id)?.placed == Placed3D.none)
    }

    @Test func aFlatFrameLeavesItsChildrenAlone() throws {
        let card = Self.card("C", at: Vec2(400, 300), z: 200)
        let s = Self.scene([Self.frame([card], space: nil)])
        #expect(s.layer(card.id)?.placed == Placed3D.none)
    }

    @Test func aTiltTurnsInTheSpaceSeenByTheCamera() throws {
        // The tilt's own depth no longer counts: the camera's does.
        let card = Self.card("C", at: Vec2(300, 200), tilt: Tilt(x: 20, y: 50, depth: 99))
        let s = Self.scene([Self.frame([card])])
        let camera = Camera3D(distance: 1000, vanishingPoint: Vec2(400, 300))
        let pose = Pose3D.layer(position: Vec2(300, 200), anchor: Vec2(50, 40), tilt: Vec2(20, 50))
        #expect(try #require(s.layer(card.id)).projection == camera.projection(of: pose))
    }

    @Test func aHingedTiltTurnsOnItsEdge() throws {
        // Page Turn's hinge: the left edge stays where it is, wherever the
        // page swings.
        let card = Self.card("C", at: Vec2(300, 200), tilt: Tilt(x: 0, y: 70, hinge: Vec2(0, 0.5)))
        let p = try #require(Self.scene([Self.frame([card])]).layer(card.id)).projection
        let camera = Camera3D(distance: 1000, vanishingPoint: Vec2(400, 300))
        #expect(close(p.apply(Vec2(0, 0)), camera.project(Vec3(250, 160, 0))))
        #expect(close(p.apply(Vec2(0, 80)), camera.project(Vec3(250, 240, 0))))
        // The free edge has swung away and in.
        #expect(p.apply(Vec2(100, 40))!.x < 300)
    }

    @Test func theVanishingPointIsAShareOfTheFrame() throws {
        var space = Space3D(distance: 1000)
        space.vanishingPoint = Vec2(0, 0)
        let card = Self.card("C", at: Vec2(400, 300), z: -1000)
        let p = try #require(Self.scene([Self.frame([card], space: space)]).layer(card.id)).projection
        // Twice as far: halfway to the frame's top-left.
        #expect(close(p.apply(Vec2(50, 40)), Vec2(200, 150)))
    }

    @Test func isometricShowsNoPerspective() throws {
        let near = Self.card("Near", at: Vec2(300, 300), z: 500)
        let far = Self.card("Far", at: Vec2(500, 300), z: -500)
        let s = Self.scene([Self.frame([near, far], space: Space3D(isIsometric: true))])
        let a = try #require(s.layer(near.id)).projection, b = try #require(s.layer(far.id)).projection
        #expect(a.isAffine && b.isAffine)
        #expect(abs(a.determinant - b.determinant) < 1e-9)
        // Still drawn in depth order.
        #expect(s.layer(near.id)!.placed.depth > s.layer(far.id)!.placed.depth)
    }

    @Test func depthFadesAndBlursWhatIsBehindThePlane() throws {
        let space = Space3D(distance: 1000, depthFade: 0.5, depthBlur: 10)
        let front = Self.card("Front", at: Vec2(400, 300), z: 100)
        let half = Self.card("Half", at: Vec2(400, 300), z: -400)
        let far = Self.card("Far", at: Vec2(400, 300), z: -2000)
        let s = Self.scene([Self.frame([front, half, far], space: space)])
        // The frame's longer side is 800: half of it back is half the way.
        #expect(s.layer(front.id)?.opacity == 1 && s.layer(front.id)?.blur == 0)
        #expect(abs(s.layer(half.id)!.opacity - 0.75) < 1e-9 && abs(s.layer(half.id)!.blur - 5) < 1e-9)
        // Past the reach it is the full amount.
        #expect(abs(s.layer(far.id)!.opacity - 0.5) < 1e-9 && abs(s.layer(far.id)!.blur - 10) < 1e-9)
    }

    @Test func aBackTurnedToTheCameraShowsAsSet() throws {
        let space = Space3D(distance: 1000, backOpacity: 0.25)
        let away = Self.card("Away", at: Vec2(400, 300), tilt: Tilt(x: 0, y: 160))
        let facing = Self.card("Facing", at: Vec2(400, 300), tilt: Tilt(x: 0, y: 20))
        let s = Self.scene([Self.frame([away, facing], space: space)])
        #expect(s.layer(away.id)?.opacity == 0.25)
        #expect(s.layer(facing.id)?.opacity == 1)
    }

    @Test func aLayerAtTheCameraIsNotDrawn() throws {
        let s = Self.scene([Self.frame([Self.card("C", at: Vec2(400, 300), z: 990)])])
        #expect(s.layers[1].opacity == 0)
    }

    @Test func aGroupInsideIsAFlatCard() throws {
        let inner = Self.card("Inner", at: Vec2(50, 40), z: 300)
        var group = Layer(name: "G", content: .group(GroupContent(children: [inner])), size: Size2(100, 80),
                          position: Vec2(400, 300))
        group.transform.z = -200
        let s = Self.scene([Self.frame([group])])
        #expect(s.layer(group.id)?.placed.depth == -200)
        #expect(s.layer(inner.id)?.placed == Placed3D.none)
    }

    @Test func theCacheKeepsUpWithTheFrame() throws {
        // Children no action reaches are kept between evaluations; their
        // place must still follow a change to the frame's camera.
        let cache = EvaluationCache()
        let card = Self.card("C", at: Vec2(300, 300), z: -300)
        let first = Self.frame([card])
        _ = Self.scene([first], cache: cache)
        var second = first
        second.space3D = Space3D(distance: 500, depthFade: 0.3)
        let cached = Self.scene([second], cache: cache)
        let fresh = Self.scene([second])
        #expect(cached.layer(card.id) == fresh.layer(card.id))
        // And with an action on the frame, so it is not still as a whole.
        let move = Action(target: first.id, start: 0, duration: 1, easing: .linear,
                          spec: .move(MoveAction(mode: .by, end: Vec2(10, 0))))
        let a = Self.scene([second], actions: [move], at: 0.5, cache: cache)
        let b = Self.scene([second], actions: [move], at: 0.5)
        #expect(a.layer(card.id) == b.layer(card.id))
    }

    @Test func theDrawingOrderIsFarToNearInASpace() throws {
        let back = Self.card("Back", at: Vec2(400, 300), z: -100)
        let front = Self.card("Front", at: Vec2(400, 300), z: 100)
        let tie1 = Self.card("Tie1", at: Vec2(400, 300))
        let tie2 = Self.card("Tie2", at: Vec2(400, 300))
        let outside = Self.card("Outside", at: Vec2(100, 100))
        let s = Self.scene([Self.frame([front, tie1, back, tie2]), outside])
        let names = s.drawingOrder().map { i in
            [front.id: "Front", tie1.id: "Tie1", back.id: "Back", tie2.id: "Tie2", outside.id: "Outside"][s.layers[i].id] ?? "F"
        }
        #expect(names == ["F", "Back", "Tie1", "Tie2", "Front", "Outside"])
        // A scene with nothing in 3D is drawn in its own order.
        let flat = Self.scene([outside, Self.frame([front, back], space: nil)])
        #expect(flat.drawingOrder() == Array(flat.layers.indices))
    }

    @Test func aMaskInASpaceIsPlacedThereToo() throws {
        var mask = Self.card("Mask", at: Vec2(400, 300), z: 150)
        mask.isMask = true
        let masked = Self.card("Masked", at: Vec2(420, 300), z: -50)
        let s = Self.scene([Self.frame([mask, masked])])
        let m = try #require(s.mask(mask.id)), l = try #require(s.layer(masked.id))
        let resolvedMask = try #require(l.mask)
        let expected = m.projection.then(try #require(l.projection.inverted))
        let probe = Vec2(30, 20)
        #expect(close(resolvedMask.transform.apply(probe), expected.apply(probe), 1e-6))
        #expect(m.placed != Placed3D.none)
    }

    @Test func motionBlurCopiesFollowTheCamera() throws {
        let card = Self.card("C", at: Vec2(300, 300), z: 300)
        var move = Action(target: card.id, start: 0, duration: 1, easing: .linear,
                          spec: .move(MoveAction(mode: .by, end: Vec2(200, 0))))
        move.motionBlur = 0.5
        let project = Project(composition: Composition(width: 800, height: 600, frameRate: .fps30),
                              layers: [Self.frame([card])], actions: [move])
        let s = evaluate(project, at: 0.5, motionBlur: .export)
        guard case .exact(let moments) = try #require(s.layer(card.id)).motion else {
            Issue.record("an exact spread")
            return
        }
        // Each moment is the card seen through the camera, 300 nearer, so
        // a third larger than flat.
        let first = try #require(moments.first)
        let w = first.apply(Vec2(100, 40))!.x - first.apply(Vec2(0, 40))!.x
        #expect(abs(w - 100 / 0.7) < 1e-6)
    }
}
