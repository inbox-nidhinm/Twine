import Foundation
import Testing
import CoreGraphics
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// Gradients drawn off screen, as exports are.
@Suite struct GradientRenderingTests {
    private func rgb(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    /// A 200 by 100 card filling its scene, painted red to blue.
    private func card(_ paint: (MotionModel.Gradient) -> Paint, end: Vec2, across: Double? = nil) throws -> CGImage {
        let g = MotionModel.Gradient(stops: [GradientStop(position: 0, color: RGBA(1, 0, 0)), GradientStop(position: 1, color: RGBA(0, 0, 1))],
                                     start: Vec2(0.5, 0.5), end: end, across: across)
        let layer = Layer(name: "C", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: paint(g))])),
                          size: Size2(200, 100), position: Vec2(100, 50))
        let project = Project(composition: Composition(width: 200, height: 100), layers: [layer])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 200, pixelHeight: 100))
        return try #require(renderer.image(of: evaluate(project, at: 0)))
    }

    @Test func anAngularGradientTurnsClockwiseFromItsEnd() throws {
        // From the right of the centre: a quarter turn on is straight down,
        // three quarters straight up.
        let image = try card({ .angularGradient($0) }, end: Vec2(1, 0.5))
        let below = rgb(image, 100, 95), above = rgb(image, 100, 5), left = rgb(image, 5, 50)
        #expect(abs(below.b - 64) < 20 && abs(below.r - 191) < 20, "a quarter of the way: mostly red")
        #expect(abs(above.b - 191) < 20 && abs(above.r - 64) < 20, "three quarters: mostly blue")
        #expect(abs(left.b - 128) < 20)
    }

    @Test func anAngularGradientStartsWhereItsEndPointsInPixels() throws {
        // The end at the bottom-right corner is 26.6° below level in this
        // 2:1 card (45° as fractions of the box): just past 30° is just
        // past the start, so nearly all red.
        let image = try card({ .angularGradient($0) }, end: Vec2(1, 1))
        let a = 32.0 * .pi / 180
        let just = rgb(image, Int(100 + cos(a) * 45), Int(50 + sin(a) * 45))
        #expect(just.r > 220 && just.b < 35)
    }

    /// How far through red to blue a pixel is, from its blue.
    private func share(_ image: CGImage, _ x: Double, _ y: Double) -> Double {
        Double(rgb(image, Int(x.rounded()), Int(y.rounded())).b) / 255
    }

    @Test func aLevelOvalReachesLessAcross() throws {
        // 100 px along, 40 across: 38 px down is nearly the edge, 38 px
        // right well inside.
        let image = try card({ .radialGradient($0) }, end: Vec2(1, 0.5), across: 0.4)
        #expect(abs(share(image, 100, 88) - 0.95) < 0.06)
        #expect(abs(share(image, 138, 50) - 0.38) < 0.06)
    }

    @Test func aTurnedOvalFollowsItsLine() throws {
        // From the centre to (150, 100) in pixels: 70.7 px at 45°, and half
        // that across. Along the line a point 20 px out is 28% of the way;
        // across it, the same 20 px is 57%.
        let image = try card({ .radialGradient($0) }, end: Vec2(0.75, 1), across: 0.5)
        let d = 20 / 2.0.squareRoot()
        #expect(abs(share(image, 100 + d, 50 + d) - 0.283) < 0.06)
        #expect(abs(share(image, 100 - d, 50 + d) - 0.566) < 0.06)
        // The corners lie past the oval: the last colour, not nothing.
        let corner = rgb(image, 2, 2)
        #expect(corner.b > 230 && corner.r < 25)
        let other = rgb(image, 197, 97)
        #expect(other.b > 230 && other.r < 25)
    }

    @Test func aCircleIsStillACircleInPixels() throws {
        // No reach across given: 30 px out is 30% whichever way.
        let image = try card({ .radialGradient($0) }, end: Vec2(1, 0.5))
        #expect(abs(share(image, 130, 50) - 0.3) < 0.06)
        #expect(abs(share(image, 100, 80) - 0.3) < 0.06)
    }
}
