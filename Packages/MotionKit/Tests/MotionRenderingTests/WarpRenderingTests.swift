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

    @Test func aPageCurlLiftsItsCornerAndStaysInItsBox() throws {
        // A 100 point square in a 200 point scene, curled halfway from its
        // top right corner.
        let layer = Layer(name: "S", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                                 fills: [Fill(paint: .color(RGBA(1, 0, 0)))])),
                          size: Size2(100, 100), position: Vec2(100, 100))
        var curl = Action(target: layer.id, start: 0, duration: 1, easing: .linear,
                          spec: .preset(PresetAction(preset: .pageCurlOut, corner: .topRight)))
        func image(at time: Double) throws -> CGImage {
            let project = Project(composition: Composition(width: 200, height: 200, background: Background(isTransparent: true)),
                                  layers: [layer], actions: [curl])
            let renderer = try #require(OffscreenRenderer(pixelWidth: 200, pixelHeight: 200))
            return try #require(renderer.image(of: evaluate(project, at: time)))
        }
        let half = try image(at: 0.5)
        #expect(alpha(half, 145, 55) == 0, "the top right corner has lifted away")
        #expect(alpha(half, 55, 145) > 200, "the bottom left is still down")
        #expect(alpha(half, 45, 100) == 0 && alpha(half, 100, 155) == 0, "the leaf never leaves the box")
        // The other way up from the bottom left.
        curl.spec = .preset(PresetAction(preset: .pageCurlOut, corner: .bottomLeft))
        let other = try image(at: 0.5)
        #expect(alpha(other, 55, 145) == 0 && alpha(other, 145, 55) > 200)
        // Curled off, nothing at all.
        #expect(alpha(try image(at: 1), 100, 100) == 0)
    }

    /// A 44 pixel level line across the middle of a 64 by 64 scene, x 10
    /// to 54, with `stroke`.
    private func line(_ stroke: Stroke) throws -> CGImage {
        let path = BezierPath(subpaths: [Subpath(points: [PathPoint(Vec2(0, 0)), PathPoint(Vec2(44, 0))], isClosed: false)])
        let layer = Layer(name: "L", content: .shape(ShapeContent(geometry: .path(path), fills: [], strokes: [stroke])),
                          size: Size2(44, 0), position: Vec2(32, 32))
        let project = Project(composition: Composition(width: 64, height: 64, background: Background(isTransparent: true)),
                              layers: [layer])
        let renderer = try #require(OffscreenRenderer(pixelWidth: 64, pixelHeight: 64))
        return try #require(renderer.image(of: evaluate(project, at: 0)))
    }

    @Test func aTrimFromBothEndsLeavesTheMiddleOpen() throws {
        var stroke = Stroke(paint: .solid(RGBA(1, 0, 0)), width: 4)
        stroke.trim = TrimRange(direction: .toMiddle, amount: 0.5)
        // A quarter of the line from each end: x 10 to 21 and 43 to 54.
        let image = try line(stroke)
        #expect(alpha(image, 13, 32) > 200 && alpha(image, 51, 32) > 200)
        #expect(alpha(image, 32, 32) == 0 && alpha(image, 25, 32) == 0 && alpha(image, 39, 32) == 0)
    }

    @Test func dotsAreRoundAndSpacedByTheirGap() throws {
        var stroke = Stroke(paint: .solid(RGBA(1, 0, 0)), width: 4, dashPattern: [0, 4])
        stroke.dotted = true
        // Dots 4 across, 8 apart from the line's start: centres at 10, 18, 26...
        let image = try line(stroke)
        #expect(alpha(image, 18, 32) > 200 && alpha(image, 26, 32) > 200)
        #expect(alpha(image, 22, 32) == 0)
        // Round: nothing at a dot's corner.
        #expect(alpha(image, 20, 34) < 60)
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
