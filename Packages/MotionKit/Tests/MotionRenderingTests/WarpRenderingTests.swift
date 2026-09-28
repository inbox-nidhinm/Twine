import Foundation
import Testing
import CoreGraphics
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// Skewed and tilted layers drawn off screen, as exports are, checked
/// against where the transform says their edges fall.
@Suite struct WarpRenderingTests {
    private func alpha(_ image: CGImage, _ x: Int, _ y: Int) -> Int {
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        return Int(bytes[3])
    }

    /// A 32 by 32 square turning about its middle, in a 64 by 64 scene.
    private func square(_ change: (inout Transform) -> Void) throws -> CGImage {
        var layer = Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                 fills: [Fill(paint: .color(RGBA(1, 0, 0)))])),
                          size: Size2(32, 32), position: Vec2(32, 32))
        change(&layer.transform)
        let project = Project(composition: Composition(width: 64, height: 64, background: Background(isTransparent: true)),
                              layers: [layer])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 64, pixelHeight: 64))
        return try #require(renderer.image(of: evaluate(project, at: 0)))
    }

    @Test func aSkewSlantsTheSides() throws {
        // 30° across: the bottom moves right by tan 30° of its height (9 px
        // each side of the middle), the top left.
        let image = try square { $0.skew = Vec2(30, 0) }
        #expect(alpha(image, 54, 46) > 200, "the bottom reaches past the square's right side")
        #expect(alpha(image, 22, 46) == 0, "and leaves its bottom-left corner")
        #expect(alpha(image, 9, 18) > 200, "the top reaches past its left side")
        #expect(alpha(image, 54, 18) == 0)
    }

    @Test func aTiltDrawsInPerspective() throws {
        // Turned 60° side to side, seen from 100 px: the right side, gone
        // away, is shorter (y 18 to 46 at x 39); the near left side longer
        // (y 13 to 51 at x 23).
        let image = try square { $0.tilt = Tilt(x: 0, y: 60, depth: 100) }
        #expect(alpha(image, 24, 15) > 200, "the near side stands taller")
        #expect(alpha(image, 37, 16) == 0, "the far side is shorter")
        #expect(alpha(image, 37, 20) > 200)
        #expect(alpha(image, 24, 32) > 200)
        #expect(alpha(image, 20, 32) == 0, "and it is narrower than it was")
        #expect(alpha(image, 42, 32) == 0)
    }
}
