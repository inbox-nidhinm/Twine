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

    @Test func aFlatFrameLeavesItsChildrenFlat() throws {
        let card = Self.card("C", at: Vec2(400, 300))
        let s = Self.scene([Self.frame([card], space: nil)])
        #expect(s.layer(card.id)?.placed == Placed3D.none)
    }

    @Test func zOutsideA3DFrameIsSeenFromItsOwnTilt() throws {
        // 600 nearer from its tilt's 1200 away: twice as big about its
        // anchor, and still in its place among its siblings.
        let card = Self.card("C", at: Vec2(400, 300), z: 600)
        let placed = try #require(Self.scene([Self.frame([card], space: nil)]).layer(card.id))
        #expect(placed.placed.depth == 0)
        let p = placed.projection
        #expect(abs(p.apply(Vec2(100, 40))!.x - p.apply(Vec2(0, 40))!.x - 200) < 1e-9)
        #expect(close(p.apply(Vec2(50, 40)), Vec2(400, 300)))
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
        // Inside the flat card, its own Z is its own perspective's, not the
        // frame's camera, and orders nothing.
        let own = try #require(s.layer(inner.id))
        #expect(own.placed.depth == 0)
        #expect(own.projection == Camera3D.ownProjection(position: Vec2(50, 40), z: 300, anchor: Vec2(50, 40), scale: Vec2(1, 1),
                                                         rotation: 0, skew: .zero, tilt: .none, size: Size2(100, 80)))
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

/// The Depth and Camera actions.
@Suite struct Actions3DTests {
    typealias F = Frame3DTests

    @Test func aDepthActionBringsALayerForward() throws {
        let card = F.card("C", at: Vec2(400, 300), z: -100)
        let frame = F.frame([card])
        let to = Action(target: card.id, start: 0, duration: 1, easing: .linear, spec: .depth(DepthAction(mode: .to, end: 300)))
        #expect(F.scene([frame], actions: [to], at: 0.5).layer(card.id)?.placed.depth == 100)
        #expect(F.scene([frame], actions: [to], at: 1).layer(card.id)?.placed.depth == 300)
        // By adds to where it starts; a starting value holds from 0 s.
        let by = Action(target: card.id, start: 1, duration: 1, easing: .linear,
                        spec: .depth(DepthAction(mode: .by, initial: -500, end: 200)))
        #expect(F.scene([frame], actions: [by], at: 0).layer(card.id)?.placed.depth == -500)
        #expect(F.scene([frame], actions: [by], at: 2).layer(card.id)?.placed.depth == -300)
    }

    @Test func aCameraActionMovesTheCamera() throws {
        let card = F.card("C", at: Vec2(400, 300), z: 200)
        let frame = F.frame([card], space: Space3D(distance: 1000))
        var end = Space3D(distance: 400)
        end.depthFade = 1
        let move = Action(target: frame.id, start: 0, duration: 1, easing: .linear, spec: .camera(CameraAction(end: end)))
        func width(at t: Double) throws -> Double {
            let p = try #require(F.scene([frame], actions: [move], at: t).layer(card.id)).projection
            return p.apply(Vec2(100, 40))!.x - p.apply(Vec2(0, 40))!.x
        }
        #expect(abs(try width(at: 0) - 100 / 0.8) < 1e-9)
        // Half way the camera is 700 away.
        #expect(abs(try width(at: 0.5) - 100 / (1 - 200.0 / 700)) < 1e-9)
        #expect(abs(try width(at: 1) - 100 / 0.5) < 1e-9)
    }

    @Test func aCameraBlendsItsNumbersButNotIsometric() {
        let a = Space3D(distance: 1000, isIsometric: true, vanishingPoint: Vec2(0, 0), depthFade: 0, depthBlur: 0, backOpacity: 1)
        let b = Space3D(distance: 200, isIsometric: false, vanishingPoint: Vec2(1, 1), depthFade: 1, depthBlur: 10, backOpacity: 0)
        let half = Space3D.interpolate(a, b, 0.5)
        #expect(half.distance == 600 && half.vanishingPoint == Vec2(0.5, 0.5))
        #expect(half.depthFade == 0.5 && half.depthBlur == 5 && half.backOpacity == 0.5)
        #expect(half.isIsometric)
        // Overshooting easings never take the camera past it, or fades out of range.
        let past = Space3D.interpolate(a, b, 1.6)
        #expect(past.distance >= 1 && past.depthFade == 1 && past.backOpacity == 0)
    }

    @Test func aCameraActionOnAFlatFrameDoesNothing() throws {
        let card = F.card("C", at: Vec2(400, 300), z: 200)
        let frame = F.frame([card], space: nil)
        let move = Action(target: frame.id, start: 0, duration: 1, easing: .linear,
                          spec: .camera(CameraAction(end: Space3D(distance: 100))))
        #expect(F.scene([frame], actions: [move], at: 1).layer(card.id) == F.scene([frame]).layer(card.id))
    }

    @Test func depthBlursAsItMoves() throws {
        let card = F.card("C", at: Vec2(400, 300))
        var move = Action(target: card.id, start: 0, duration: 1, easing: .linear,
                          spec: .depth(DepthAction(mode: .by, end: 600)))
        move.motionBlur = 0.5
        #expect(move.canMotionBlur)
        let project = Project(composition: Composition(width: 800, height: 600, frameRate: .fps30),
                              layers: [F.frame([card])], actions: [move])
        guard case .exact(let moments) = try #require(evaluate(project, at: 0.5, motionBlur: .export).layer(card.id)).motion else {
            Issue.record("an exact spread")
            return
        }
        // Nearer at the shutter's close than at its open.
        let w = { (p: Projective) in p.apply(Vec2(100, 40))!.x - p.apply(Vec2(0, 40))!.x }
        #expect(w(moments.last!) > w(moments.first!))
    }

    @Test func theNewActionsKeepInFiles() throws {
        let actions = [Action(target: UUID(), start: 0, duration: 1, easing: .linear,
                              spec: .depth(DepthAction(mode: .by, initial: -20, end: 300))),
                       Action(target: UUID(), start: 0, duration: 1, easing: .linear,
                              spec: .camera(CameraAction(initial: Space3D(distance: 900), end: Space3D(distance: 300, depthBlur: 4))))]
        let back = try JSONDecoder().decode([Action].self, from: JSONEncoder().encode(actions))
        #expect(back == actions)
    }
}

/// Bend and the camera's orbit.
@Suite struct BendAndOrbitTests {
    typealias F = Frame3DTests

    private func close(_ a: Vec2?, _ b: Vec2?, _ tolerance: Double = 1e-6) -> Bool {
        guard let a, let b else { return false }
        return abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    @Test func aBoxGoesOntoAnyFourCorners() throws {
        let corners = [Vec2(10, 20), Vec2(210, 5), Vec2(190, 160), Vec2(30, 140)]
        let p = try #require(Projective.box(Size2(100, 50), onto: corners))
        for (point, corner) in zip([Vec2(0, 0), Vec2(100, 0), Vec2(100, 50), Vec2(0, 50)], corners) {
            #expect(close(p.apply(point), corner, 1e-9))
        }
        #expect(Projective.box(Size2(100, 50), onto: [Vec2(0, 0), Vec2(1, 1), Vec2(2, 2), Vec2(3, 3)]) == nil)
    }

    @Test func aCurveKeepsItsMiddleAndBendsItsEdgesAway() {
        let curve = Curve(size: Size2(200, 100), bend: Vec2(90, 0))
        let middle = curve.point(100, 50)
        #expect(abs(middle.x - 100) < 1e-9 && abs(middle.z) < 1e-9)
        // A quarter of a circle: the edges are r sin 45° out and r (1 - cos 45°) back.
        let r = 200 / (Double.pi / 2)
        let edge = curve.point(200, 50)
        #expect(abs(edge.x - (100 + r * sin(.pi / 4))) < 1e-9 && abs(edge.z - r * (cos(.pi / 4) - 1)) < 1e-9)
        // Hollow, the edges come forward instead.
        #expect(Curve(size: Size2(200, 100), bend: Vec2(-90, 0)).point(200, 50).z > 0)
        // Straight along the other way.
        #expect(abs(curve.point(100, 0).y) < 1e-9 && abs(curve.point(100, 0).z) < 1e-9)
    }

    @Test func aBentLayerIsDrawnFromItsPoints() throws {
        var card = F.card("C", at: Vec2(400, 300))
        card.transform.bend = Vec2(90, 0)
        let flat = try #require(F.scene([card]).layer(card.id))
        let mesh = try #require(flat.placed.mesh)
        #expect(mesh.columns == BentMesh.bentCells && mesh.rows == BentMesh.straightCells)
        #expect(mesh.points.count == 17 * 5)
        // Outside a 3D space it keeps its place among its siblings.
        #expect(flat.placed.depth == 0)
        // Its middle stays where it was; its sides come in and shrink back.
        let middle = mesh.points[2 * 17 + 8]
        #expect(close(middle, Vec2(400, 300), 1e-9))
        let right = mesh.points[2 * 17 + 16]
        #expect(right.x < 450 && right.x > 400)
        // The outline goes through its corners.
        #expect(close(flat.projection.apply(Vec2(100, 0)), mesh.points[16], 1e-9))
        // In a 3D frame it is ordered by its middle.
        var deep = card
        deep.transform.z = -150
        #expect(try #require(F.scene([F.frame([deep])]).layer(card.id)).placed.depth == -150)
    }

    @Test func aBendActionCurvesALayer() throws {
        let card = F.card("C", at: Vec2(400, 300))
        let bend = Action(target: card.id, start: 0, duration: 1, easing: .linear,
                          spec: .bend(BendAction(mode: .by, end: Vec2(0, 60))))
        #expect(F.scene([card], actions: [bend], at: 0).layer(card.id)?.placed == Placed3D.none)
        let half = try #require(F.scene([card], actions: [bend], at: 0.5).layer(card.id))
        #expect(half.warp.bend == Vec2(0, 30))
        #expect(half.placed.mesh?.rows == BentMesh.bentCells)
    }

    @Test func theOrbitTurnsTheWholeSpace() throws {
        let front = F.card("Front", at: Vec2(400, 300), z: 200)
        let back = F.card("Back", at: Vec2(400, 300), z: -200)
        var space = Space3D(distance: 1000)
        space.orbit = Vec2(0, 180)
        let s = F.scene([F.frame([front, back], space: space)])
        // Half way round, the back is nearest, and the front turned away.
        #expect(abs(s.layer(back.id)!.placed.depth - 200) < 1e-9)
        #expect(abs(s.layer(front.id)!.placed.depth + 200) < 1e-9)
        // A quarter turn swings the front card to the right of the middle.
        space.orbit = Vec2(0, 90)
        let q = F.scene([F.frame([front], space: space)])
        #expect(try #require(q.layer(front.id)).projection.apply(Vec2(50, 40))!.x > 590)
        // A Camera action spins it.
        let spin = Action(target: q.layers[0].id, start: 0, duration: 1, easing: .linear,
                          spec: .camera(CameraAction(initial: Space3D(distance: 1000), end: Space3D(distance: 1000, orbit: Vec2(0, 360)))))
        let frame = F.frame([front], space: Space3D(distance: 1000))
        let spinning = Action(target: frame.id, start: spin.start, duration: 1, easing: .linear, spec: spin.spec)
        #expect(abs(F.scene([frame], actions: [spinning], at: 0.5).layer(front.id)!.placed.depth + 200) < 1e-9)
    }
}
