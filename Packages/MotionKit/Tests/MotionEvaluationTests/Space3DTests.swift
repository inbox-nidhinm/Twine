import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

/// The shared 3D space's maths: a flat layer placed in it and seen through
/// its camera.
@Suite struct Space3DTests {
    private func close(_ a: Vec2?, _ b: Vec2?, _ tolerance: Double = 1e-6) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance
    }

    private let corners = [Vec2(0, 0), Vec2(120, 0), Vec2(120, 80), Vec2(0, 80), Vec2(37, 51)]

    @Test func aLayerSeenThroughTheCameraLandsWhereItsPointsDo() {
        let camera = Camera3D(distance: 900, vanishingPoint: Vec2(400, 300))
        let pose = Pose3D.layer(position: Vec2(320, 260), z: -140, anchor: Vec2(60, 40), scale: Vec2(1.2, 0.9),
                                rotation: 17, tilt: Vec2(-25, 40))
        let projection = camera.projection(of: pose)
        for p in corners {
            #expect(close(projection.apply(p), camera.project(pose.apply(Vec3(p.x, p.y, 0)))))
        }
    }

    @Test func aTiltIsTheSameTurnSeenFromAboveItsAnchor() {
        // A layer's own tilt is a camera of its own, over its anchor, at
        // the tilt's depth: the shared space must agree with it exactly.
        let tilt = Tilt(x: 30, y: -50, depth: 700)
        let flat = Projective.layer(position: Vec2(200, 150), anchor: Vec2(60, 40), scale: Vec2(1.5, 1),
                                    rotation: 25, skew: .zero, tilt: tilt)
        let pose = Pose3D.layer(position: Vec2(200, 150), anchor: Vec2(60, 40), scale: Vec2(1.5, 1),
                                rotation: 25, tilt: Vec2(tilt.x, tilt.y))
        let shared = Camera3D(distance: tilt.depth, vanishingPoint: Vec2(200, 150)).projection(of: pose)
        for p in corners { #expect(close(flat.apply(p), shared.apply(p))) }
    }

    @Test func nearerIsLargerAndAwayIsSmaller() {
        let camera = Camera3D(distance: 1000, vanishingPoint: Vec2(0, 0))
        func width(at z: Double) -> Double {
            let p = camera.projection(of: .layer(position: .zero, z: z, anchor: Vec2(50, 50)))
            return p.apply(Vec2(100, 50))!.x - p.apply(Vec2(0, 50))!.x
        }
        #expect(abs(width(at: 0) - 100) < 1e-9)
        #expect(abs(width(at: 100) - 100 / 0.9) < 1e-9)
        #expect(abs(width(at: -1000) - 50) < 1e-9)
    }

    @Test func behindTheViewerCannotBeSeen() {
        let camera = Camera3D(distance: 500, vanishingPoint: .zero)
        #expect(camera.project(Vec3(10, 10, 600)) == nil)
        #expect(camera.projection(of: .translation(Vec3(0, 0, 600))).apply(.zero) == nil)
    }

    @Test func isometricIgnoresDepth() {
        let camera = Camera3D(distance: nil, vanishingPoint: Vec2(400, 300))
        let near = camera.projection(of: .layer(position: Vec2(100, 100), z: 300, anchor: .zero))
        let far = camera.projection(of: .layer(position: Vec2(100, 100), z: -300, anchor: .zero))
        #expect(near == far)
        #expect(near.isAffine)
        // Turned on y, a 100 wide layer is cos 60° as wide, whatever its depth.
        let turned = camera.projection(of: .layer(position: .zero, anchor: .zero, tilt: Vec2(0, 60)))
        #expect(abs(turned.apply(Vec2(100, 0))!.x - 50) < 1e-9)
    }

    @Test func aCardTurnedAwayShowsItsBack() {
        let camera = Camera3D(distance: 1200, vanishingPoint: Vec2(400, 300))
        func front(_ turn: Double, x: Double = 400) -> Bool {
            camera.seesFront(of: .layer(position: Vec2(x, 300), anchor: Vec2(50, 50), tilt: Vec2(0, turn)),
                             at: Vec2(50, 50))
        }
        #expect(front(0))
        #expect(front(80))
        #expect(!front(180))
        #expect(!front(100))
        // Edge on to the middle of the view, but off to the side: the eye
        // sees round it, onto its face.
        #expect(front(90, x: 900) != front(90, x: -100))
        #expect(!Camera3D(distance: nil, vanishingPoint: .zero)
            .seesFront(of: .turnY(degrees: 120), at: .zero))
    }

    @Test func posesCombineInOrder() {
        // Half a turn on y, then moved: the layer's right edge lands left.
        let pose = Pose3D.turnY(degrees: 180).then(.translation(Vec3(10, 0, 0)))
        let p = pose.apply(Vec3(5, 0, 0))
        #expect(abs(p.x - 5) < 1e-9 && abs(p.z) < 1e-9)
        #expect(Placed3D(.translation(Vec3(0, 0, 42)), camera: Camera3D(distance: 900, vanishingPoint: .zero),
                         middle: Vec2(3, 4)).depth == 42)
        #expect(Placed3D.none.depth == 0)
    }
}
