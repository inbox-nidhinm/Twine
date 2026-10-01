import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

private func near(_ a: Double, _ b: Double, _ e: Double = 1e-6) -> Bool { abs(a - b) < e }
private func near(_ a: Vec2?, _ b: Vec2, _ e: Double = 1e-6) -> Bool { a.map { near($0.x, b.x, e) && near($0.y, b.y, e) } ?? false }

@Suite struct WarpTests {
    private func square() -> Layer {
        Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [])),
              size: Size2(100, 100), position: Vec2(500, 300))
    }

    @Test func aSkewSlantsAboutTheAnchor() {
        var layer = square()
        layer.transform.skew = Vec2(45, 0)
        let scene = evaluateDesign(Project(layers: [layer]))
        let corners = scene.worldCorners(of: layer.id)!
        // tan 45° is 1: the bottom moves right by half the height, the top left.
        #expect(near(corners[0], Vec2(400, 250)))
        #expect(near(corners[2], Vec2(600, 350)))
        // Flat, so editing's transform and what is drawn agree.
        #expect(scene.worldProjection(of: layer.id)!.isAffine)
    }

    @Test func aTiltTurnsInPerspectiveAboutTheAnchor() {
        var layer = square()
        layer.transform.tilt = Tilt(x: 0, y: 60, depth: 200)
        let world = evaluateDesign(Project(layers: [layer])).worldProjection(of: layer.id)!
        // The anchor stays put.
        #expect(near(world.apply(Vec2(50, 50)), Vec2(500, 300)))
        // The right side goes away, so it is nearer the middle and shorter
        // than the left.
        let right = world.apply(Vec2(100, 0))!, left = world.apply(Vec2(0, 0))!
        #expect(right.x - 500 < 500 - left.x)
        #expect(300 - right.y < 300 - left.y)
        // Half a turn shows the back, mirrored, whatever the depth.
        layer.transform.tilt = Tilt(x: 0, y: 180, depth: 200)
        let back = evaluateDesign(Project(layers: [layer])).worldProjection(of: layer.id)!
        #expect(near(back.apply(Vec2(100, 50)), Vec2(450, 300), 1e-4))
    }

    @Test func aHingedTiltTurnsOnItsEdgeLikeAPage() {
        var layer = square()
        layer.transform.tilt = Tilt(x: 0, y: -60, hinge: Vec2(0, 0.5))
        let world = evaluateDesign(Project(layers: [layer])).worldProjection(of: layer.id)!
        // The spine, the left edge, stays put.
        #expect(near(world.apply(Vec2(0, 0)), Vec2(450, 250), 1e-6))
        #expect(near(world.apply(Vec2(0, 100)), Vec2(450, 350), 1e-6))
        // The free edge comes towards the viewer, so it is drawn taller than
        // the spine, and nearer it.
        let top = world.apply(Vec2(100, 0))!, bottom = world.apply(Vec2(100, 100))!
        #expect(bottom.y - top.y > 100)
        #expect(top.x > 450 && top.x < 550)
        // Seen from 1 / 0.35 of its longer side, as the onboarding's pages,
        // so even a wide layer never reaches the eye.
        layer.size = Size2(3000, 100)
        layer.transform.anchor = Vec2(1500, 50)
        layer.transform.tilt = Tilt(x: 0, y: -89, hinge: Vec2(0, 0.5))
        let wide = evaluateDesign(Project(layers: [layer])).worldProjection(of: layer.id)!
        #expect(wide.apply(Vec2(3000, 50)) != nil)
        // A turned layer turns on its own edge.
        layer = square()
        layer.transform.rotation = 90
        layer.transform.tilt = Tilt(x: 0, y: -60, hinge: Vec2(0, 0.5))
        let turned = evaluateDesign(Project(layers: [layer])).worldProjection(of: layer.id)!
        #expect(near(turned.apply(Vec2(0, 0)), Vec2(550, 250), 1e-6))
        #expect(near(turned.apply(Vec2(0, 100)), Vec2(450, 250), 1e-6))
        // Files without one read as before, and one is written only when set.
        let plain = try! JSONEncoder().encode(Tilt(x: 0, y: 10))
        #expect(!String(decoding: plain, as: UTF8.self).contains("hinge"))
        let hinged = Tilt(x: 0, y: 10, hinge: Vec2(1, 0.5))
        #expect(try! JSONDecoder().decode(Tilt.self, from: JSONEncoder().encode(hinged)) == hinged)
    }

    @Test func projectionsComposeAndInvert() {
        let a = Projective.layer(position: Vec2(10, 20), anchor: Vec2(5, 5), scale: Vec2(2, 1), rotation: 30,
                                 skew: Vec2(10, -5), tilt: Tilt(x: 20, y: -35, depth: 400))
        let b = Projective.layer(position: Vec2(-40, 7), anchor: .zero, scale: Vec2(1, 1), rotation: -10,
                                 skew: .zero, tilt: Tilt(x: -15, y: 10, depth: 900))
        let p = Vec2(3, -8)
        #expect(near(a.then(b).apply(p), b.apply(a.apply(p)!)!, 1e-9))
        #expect(near(a.inverted!.apply(a.apply(p)!), p, 1e-9))
        // With no tilt it is exactly the flat transform.
        let flat = Projective.layer(position: Vec2(10, 20), anchor: Vec2(5, 5), scale: Vec2(2, 1), rotation: 30,
                                    skew: Vec2(10, -5), tilt: .none)
        let affine = Affine.layer(position: Vec2(10, 20), anchor: Vec2(5, 5), scale: Vec2(2, 1), rotation: 30, skew: Vec2(10, -5))
        #expect(flat.isAffine && near(flat.apply(p), affine.apply(p), 1e-9))
    }

    @Test func olderFilesHaveNeitherAndStraightLayersWriteNeither() throws {
        let old = #"{"position":{"x":1,"y":2},"anchor":{"x":0,"y":0},"scale":{"x":1,"y":1},"isScaleLinked":true,"rotation":0}"#
        let t = try JSONDecoder().decode(Transform.self, from: Data(old.utf8))
        #expect(t.skew == .zero && t.tilt == .none)
        let written = String(decoding: try JSONEncoder().encode(t), as: UTF8.self)
        #expect(!written.contains("skew") && !written.contains("tilt"))
        var warped = t
        warped.skew = Vec2(5, 0)
        warped.tilt = Tilt(x: 10, y: 0, depth: 800)
        #expect(try JSONDecoder().decode(Transform.self, from: JSONEncoder().encode(warped)) == warped)
    }

    @Test func skewAndTiltActionsAnimate() {
        let layer = square()
        let skew = Action(target: layer.id, start: 0, duration: 1, easing: .preset(.none, intensity: 0),
                          spec: .skew(SkewAction(mode: .by, end: Vec2(20, 0))))
        let tilt = Action(target: layer.id, start: 0, duration: 1, easing: .preset(.none, intensity: 0),
                          spec: .tilt(TiltAction(mode: .to, initial: Tilt(x: 0, y: 0, depth: 600), end: Tilt(x: 40, y: 0, depth: 600))))
        let tracks = ActionTracks([skew, tilt])
        #expect(near(tracks.state(of: layer, at: 0.5).skew.x, 10))
        #expect(near(tracks.state(of: layer, at: 0.5).tilt.x, 20))
        #expect(near(tracks.state(of: layer, at: 2).skew.x, 20))
        // They reach what is drawn.
        let scene = evaluate(Project(layers: [layer], actions: [skew, tilt]), at: 2)
        #expect(scene.layer(layer.id)?.skew == Vec2(20, 0))
        #expect(scene.layer(layer.id)?.tilt == Tilt(x: 40, y: 0, depth: 600))
    }
}
