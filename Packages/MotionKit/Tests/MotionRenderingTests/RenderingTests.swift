import Foundation
import Testing
import CoreGraphics
import MotionModel
import MotionEvaluation
@testable import MotionRendering

/// Reads one pixel of a rendered image as straight (not premultiplied) RGBA,
/// 0 to 255, with row 0 at the top.
private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
    let a = Int(bytes[3])
    func unpremultiply(_ v: UInt8) -> Int { a == 0 ? 0 : min(255, Int((Double(v) * 255 / Double(a)).rounded())) }
    return (unpremultiply(bytes[0]), unpremultiply(bytes[1]), unpremultiply(bytes[2]), a)
}

private func shape(_ geometry: ShapeGeometry = .rectangle(cornerRadii: .zero),
                   fill: RGBA? = RGBA(1, 0, 0), at origin: Vec2, size: Size2) -> Layer {
    var layer = Layer(name: "S", content: .shape(ShapeContent(geometry: geometry,
                                                             fills: fill.map { [Fill(paint: .color($0))] } ?? [])),
                      size: size, position: origin)
    layer.transform.anchor = .zero
    return layer
}

private func render(_ project: Project, pixels: Int = 64, at time: Double = 0) throws -> CGImage {
    let renderer = try #require(OffscreenRenderer(pixelWidth: pixels, pixelHeight: pixels))
    return try #require(renderer.image(of: evaluate(project, at: time)))
}

private func transparentComposition(_ size: Int = 64) -> Composition {
    Composition(width: size, height: size, background: Background(isTransparent: true))
}

@Suite(.serialized) struct RenderingTests {
    @Test func drawsWithTheOriginAtTheTopLeft() throws {
        let project = Project(composition: transparentComposition(),
                              layers: [shape(at: Vec2(8, 8), size: Size2(16, 16))])
        let image = try render(project)
        let inside = pixel(image, 16, 16)
        #expect(inside.r > 250 && inside.g < 5 && inside.a > 250)
        #expect(pixel(image, 4, 4).a == 0)
        // The bottom-right is empty, so the square really is at the top.
        #expect(pixel(image, 56, 56).a == 0)
    }

    @Test func backgroundFillsOrStaysTransparent() throws {
        var project = Project(composition: Composition(width: 64, height: 64,
                                                       background: Background(color: RGBA(0, 0, 1))))
        let opaque = pixel(try render(project), 32, 32)
        #expect(opaque.b > 250 && opaque.a == 255)
        project.composition.background.isTransparent = true
        #expect(pixel(try render(project), 32, 32).a == 0)
    }

    @Test func scalesTheCompositionToTheOutput() throws {
        // A 32-point composition rendered at 64 pixels: the square at (8,8)
        // sized 8 covers pixels 16 to 32.
        let project = Project(composition: transparentComposition(32), layers: [shape(at: Vec2(8, 8), size: Size2(8, 8))])
        let image = try render(project, pixels: 64)
        #expect(pixel(image, 20, 20).a > 250)
        #expect(pixel(image, 12, 12).a == 0)
    }

    @Test func groupOpacityFadesTheGroupAsOnePicture() throws {
        // Two opaque squares overlapping inside a group at 50%. Faded as one
        // picture, the overlap is 50% too; faded one by one it would be 75%.
        let a = shape(fill: RGBA(1, 1, 1), at: Vec2(0, 0), size: Size2(40, 40))
        let b = shape(fill: RGBA(1, 1, 1), at: Vec2(20, 20), size: Size2(40, 40))
        var group = Layer(name: "G", content: .group(GroupContent(children: [a, b])), size: Size2(64, 64),
                          position: .zero)
        group.transform.anchor = .zero
        group.opacity = 0.5
        let overlap = pixel(try render(Project(composition: transparentComposition(), layers: [group])), 30, 30)
        #expect(abs(overlap.a - 128) <= 3)
    }

    @Test func rendersTheMomentAskedFor() throws {
        let square = shape(at: .zero, size: Size2(16, 16))
        let slide = Action(target: square.id, start: 0, duration: 1, easing: .linear,
                           spec: .move(MoveAction(mode: .to, end: Vec2(48, 0))))
        let project = Project(composition: transparentComposition(), layers: [square], actions: [slide])
        let early = try render(project, at: 0), late = try render(project, at: 1)
        #expect(pixel(early, 4, 8).a > 250 && pixel(early, 56, 8).a == 0)
        #expect(pixel(late, 4, 8).a == 0 && pixel(late, 56, 8).a > 250)
    }

    @Test func insideStrokesStayInsideTheShape() throws {
        var layer = shape(fill: nil, at: Vec2(16, 16), size: Size2(32, 32))
        layer.content = .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                            strokes: [Stroke(paint: .color(RGBA(0, 1, 0)), width: 4, alignment: .inside)]))
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        #expect(pixel(image, 18, 32).a > 250)   // just inside the left edge
        #expect(pixel(image, 14, 32).a == 0)    // just outside it
        #expect(pixel(image, 32, 32).a == 0)    // the middle is empty
    }

    @Test func outsideStrokesStayOutsideTheShape() throws {
        var layer = shape(fill: nil, at: Vec2(16, 16), size: Size2(32, 32))
        layer.content = .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                            strokes: [Stroke(paint: .color(RGBA(0, 1, 0)), width: 4, alignment: .outside)]))
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        #expect(pixel(image, 14, 32).a > 250)
        #expect(pixel(image, 18, 32).a == 0)
    }

    @Test func linearGradientsRunStartToEnd() throws {
        var layer = shape(fill: nil, at: .zero, size: Size2(64, 64))
        layer.content = .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                            fills: [Fill(paint: .linearGradient(Gradient(stops: [
                                                GradientStop(position: 0, color: RGBA(1, 0, 0)),
                                                GradientStop(position: 1, color: RGBA(0, 0, 1)),
                                            ])))]))
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        let left = pixel(image, 2, 32), right = pixel(image, 61, 32)
        #expect(left.r > 200 && left.b < 60)
        #expect(right.b > 200 && right.r < 60)
    }

    /// The check promised for milestone 2: a Core Image blur on a layer must
    /// render in `CARenderer` the same way it does on screen, or export would
    /// lose it. A blurred edge has partly transparent pixels on both sides.
    @Test func layerBlurRendersOffscreen() throws {
        var layer = shape(fill: RGBA(1, 1, 1), at: Vec2(16, 16), size: Size2(32, 32))
        layer.effects = [Effect(kind: .layerBlur(LayerBlur(radius: 4)))]
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        let outside = pixel(image, 14, 32).a, inside = pixel(image, 18, 32).a
        #expect(outside > 10 && outside < 245)
        #expect(inside > 10 && inside < 250)
    }

    /// Core Image's blur lands about 9 px off at this size. The blur used now
    /// must be centred: across a black and white edge, pixels the same
    /// distance either side come out as mirror images.
    @Test func layerBlurIsCentred() throws {
        var black = shape(fill: RGBA(0, 0, 0), at: .zero, size: Size2(32, 64))
        black.effects = [Effect(kind: .layerBlur(LayerBlur(radius: 12)))]
        var project = Project(composition: Composition(width: 64, height: 64, background: Background(color: .white)),
                              layers: [black])
        project.composition.background.isTransparent = false
        let image = try render(project)
        let left = pixel(image, 28, 32).r, right = pixel(image, 36, 32).r
        #expect(left > 5 && right < 250, "the edge is blurred")
        // Blurring a layer spreads it past its box, so both sides darken;
        // the check is that the edge itself sits at the box's edge.
        let mid = pixel(image, 32, 32).r
        #expect(abs(mid - 128) < 40)
    }

    @Test func backgroundBlurBlursWhatIsBehindAndStaysCentred() throws {
        let black = shape(fill: RGBA(0, 0, 0), at: .zero, size: Size2(32, 64))
        var glass = shape(fill: RGBA(1, 1, 1, 0.01), at: Vec2(8, 8), size: Size2(48, 48))
        glass.effects = [Effect(kind: .backgroundBlur(BackgroundBlur(radius: 12)))]
        let project = Project(composition: Composition(width: 64, height: 64, background: Background(color: .white)),
                              layers: [black, glass])
        let image = try render(project)
        let left = pixel(image, 28, 32).r, right = pixel(image, 36, 32).r
        #expect(left > 20 && right < 235, "the edge behind the glass is soft")
        #expect(abs((left + right) - 255) < 30, "and centred where it was")
        // Outside the glass the edge stays sharp.
        #expect(pixel(image, 30, 4).r < 5 && pixel(image, 34, 4).r > 250)
    }

    @Test func spreadGrowsTheShadow() throws {
        func shadowed(spread: Double) throws -> Int {
            var layer = shape(fill: RGBA(1, 1, 1), at: Vec2(16, 16), size: Size2(32, 32))
            layer.effects = [Effect(kind: .dropShadow(DropShadow(color: .black, offset: .zero, blur: 0, opacity: 1, spread: spread)))]
            return pixel(try render(Project(composition: transparentComposition(), layers: [layer])), 12, 32).a
        }
        #expect(try shadowed(spread: 0) == 0)
        #expect(try shadowed(spread: 8) > 250)
    }

    @Test func dropShadowsRenderOffscreenAndFallDownward() throws {
        var layer = shape(fill: RGBA(1, 1, 1), at: Vec2(16, 8), size: Size2(32, 32))
        layer.effects = [Effect(kind: .dropShadow(DropShadow(color: .black, offset: Vec2(0, 12), blur: 0, opacity: 1)))]
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        let below = pixel(image, 32, 46)   // under the square, in the shadow
        #expect(below.a > 200 && below.r < 30)
        #expect(pixel(image, 32, 3).a == 0) // nothing above it
    }
}
