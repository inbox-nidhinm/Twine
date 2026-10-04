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
    private func card(_ paint: (MotionModel.Gradient) -> Paint, end: Vec2) throws -> CGImage {
        let g = MotionModel.Gradient(stops: [GradientStop(position: 0, color: RGBA(1, 0, 0)), GradientStop(position: 1, color: RGBA(0, 0, 1))],
                                     start: Vec2(0.5, 0.5), end: end)
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
}
