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

    @Test func textDrawsInsideItsBox() throws {
        let content = TextContent(text: "IIII", fontFamily: "SF Pro", fontWeight: 900, fontSize: 40, color: RGBA(1, 0, 0))
        let size = TextLayout.size(of: content.text, style: TextStyle(content), width: nil)
        var layer = Layer(name: "T", content: .text(content), size: size, position: .zero)
        layer.transform.anchor = .zero
        layer.transform.position = Vec2(4, 4)
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        // Some red ink inside the box, none well outside it.
        var inked = 0
        for x in 4..<Int(4 + size.width) {
            let p = pixel(image, x, Int(4 + size.height / 2))
            if p.a > 200 && p.r > 200 { inked += 1 }
        }
        #expect(inked > 4)
        #expect(pixel(image, 60, 60).a == 0)
    }

    /// Text is a picture, which the offscreen renderer must not turn upside
    /// down: an underscore sits at the bottom of its box, not the top.
    @Test func textIsTheRightWayUp() throws {
        let content = TextContent(text: "____", fontFamily: "SF Pro", fontWeight: 900, fontSize: 40, color: RGBA(1, 0, 0))
        let size = TextLayout.size(of: content.text, style: TextStyle(content), width: nil)
        var layer = Layer(name: "T", content: .text(content), size: size, position: .zero)
        layer.transform.anchor = .zero
        let image = try render(Project(composition: transparentComposition(), layers: [layer]))
        func ink(rows: Range<Int>) -> Int {
            rows.reduce(0) { total, y in total + (0..<Int(size.width)).filter { pixel(image, $0, y).a > 128 }.count }
        }
        let half = Int(size.height / 2)
        #expect(ink(rows: half..<Int(size.height)) > 20)
        #expect(ink(rows: 0..<half) == 0)
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

    // MARK: Masks

    /// A red square filling the frame, masked by a white circle 32 across in
    /// the middle.
    private func masked(inverted: Bool = false, change: (inout Layer) -> Void = { _ in }) -> Project {
        var circle = shape(.ellipse(arc: .full), fill: RGBA(1, 1, 1), at: Vec2(16, 16), size: Size2(32, 32))
        change(&circle)
        var square = shape(at: .zero, size: Size2(64, 64))
        square.mask = MaskReference(layerID: circle.id, isInverted: inverted)
        return Project(composition: transparentComposition(), layers: [circle, square])
    }

    @Test func masksShowTheLayerOnlyWhereTheMaskDraws() throws {
        let image = try render(masked())
        let middle = pixel(image, 32, 32)
        // Red, not the mask's white: the mask itself does not draw.
        #expect(middle.r > 250 && middle.g < 5 && middle.a > 250)
        #expect(pixel(image, 4, 4).a == 0)
        #expect(pixel(image, 60, 60).a == 0)
    }

    @Test func invertedMasksShowTheLayerEverywhereElse() throws {
        let image = try render(masked(inverted: true))
        #expect(pixel(image, 32, 32).a == 0)
        let corner = pixel(image, 4, 4)
        #expect(corner.r > 250 && corner.g < 5 && corner.a > 250)
    }

    @Test func aMasksOpacityIsHowMuchItShows() throws {
        let image = try render(masked { $0.opacity = 0.5 })
        #expect(abs(pixel(image, 32, 32).a - 128) <= 3)
    }

    @Test func aSwitchedOffMaskShowsTheLayerWhole() throws {
        let image = try render(masked { $0.isVisible = false })
        #expect(pixel(image, 4, 4).a > 250)
        #expect(pixel(image, 32, 32).g < 5)
    }

    @Test func masksSitWhereTheirGroupsPutThem() throws {
        // The circle is 16 across at the group's origin, and the group sits
        // at (24, 24): the mask covers 24 to 40. The square is in a group of
        // its own, moved 8 left, so its own space is shifted too.
        let circle = shape(.ellipse(arc: .full), fill: RGBA(1, 1, 1), at: .zero, size: Size2(16, 16))
        var holder = Layer(name: "G", content: .group(GroupContent(children: [circle])), size: Size2(16, 16),
                           position: Vec2(24, 24))
        holder.transform.anchor = .zero
        var square = shape(at: Vec2(8, 0), size: Size2(64, 64))
        square.mask = MaskReference(layerID: circle.id)
        var outer = Layer(name: "H", content: .group(GroupContent(children: [square])), size: Size2(64, 64),
                          position: Vec2(-8, 0))
        outer.transform.anchor = .zero
        let image = try render(Project(composition: transparentComposition(), layers: [holder, outer]))
        #expect(pixel(image, 32, 32).a > 250)
        #expect(pixel(image, 20, 32).a == 0)
        #expect(pixel(image, 44, 32).a == 0)
    }
}

@Suite(.serialized) struct FrameRenderingTests {
    /// A 40 pixel red frame at (12, 12), rounded 12, with a blue square
    /// hanging off its bottom-right and a green 4 pixel stroke inside its
    /// edge.
    private func frameProject(clips: Bool) -> Project {
        let child = shape(fill: RGBA(0, 0, 1), at: Vec2(20, 20), size: Size2(40, 40))
        var frame = Layer(name: "F", content: .group(GroupContent(children: [child], clipsContent: clips, frame: FrameStyle(
            fills: [Fill(paint: .color(RGBA(1, 0, 0)))],
            strokes: [Stroke(paint: .color(RGBA(0, 1, 0)), width: 4, alignment: .inside)],
            cornerRadii: CornerRadii(all: 12)))),
            size: Size2(40, 40), position: Vec2(12, 12))
        frame.transform.anchor = .zero
        return Project(composition: transparentComposition(), layers: [frame])
    }

    @Test func aFrameDrawsItsFillBehindItsChildrenAndItsStrokeInFront() throws {
        let image = try render(frameProject(clips: true))
        let fill = pixel(image, 22, 22)
        #expect(fill.r > 250 && fill.b < 5, "the frame's own fill, where no child is")
        let child = pixel(image, 40, 40)
        #expect(child.b > 250 && child.r < 5, "the child over the fill")
        let stroke = pixel(image, 40, 50)
        #expect(stroke.g > 250 && stroke.b < 5, "the stroke over the child, inside the edge")
    }

    @Test func aFrameClipsToItsRoundedOutline() throws {
        let clipped = try render(frameProject(clips: true))
        #expect(pixel(clipped, 58, 40).a == 0, "the child outside the frame is cut off")
        #expect(pixel(clipped, 50, 50).a == 0, "and so is its part in the rounded corner")
        #expect(pixel(clipped, 13, 13).a == 0, "the frame's own corner is round")
        let open = try render(frameProject(clips: false))
        #expect(pixel(open, 58, 40).b > 250, "without clipping the child shows whole")
    }
}

/// Blend modes as the W3C's compositing spec defines them, which Figma
/// follows: `b` is what is behind, `s` the layer, each 0 to 1 in sRGB.
private enum BlendMaths {
    static func separable(_ mode: BlendMode, _ b: Double, _ s: Double) -> Double {
        switch mode {
        case .darken: return min(b, s)
        case .multiply: return b * s
        case .linearBurn: return max(0, b + s - 1)
        case .colorBurn: return b == 1 ? 1 : s == 0 ? 0 : 1 - min(1, (1 - b) / s)
        case .lighten: return max(b, s)
        case .screen: return b + s - b * s
        case .linearDodge: return min(1, b + s)
        case .colorDodge: return b == 0 ? 0 : s == 1 ? 1 : min(1, b / (1 - s))
        case .overlay: return separable(.hardLight, s, b)
        case .hardLight: return s <= 0.5 ? b * 2 * s : separable(.screen, b, 2 * s - 1)
        case .softLight:
            if s <= 0.5 { return b - (1 - 2 * s) * b * (1 - b) }
            let d = b <= 0.25 ? ((16 * b - 12) * b + 4) * b : b.squareRoot()
            return b + (2 * s - 1) * (d - b)
        case .difference: return abs(b - s)
        case .exclusion: return b + s - 2 * b * s
        default: return s
        }
    }

    typealias C = (Double, Double, Double)
    static func lum(_ c: C) -> Double { 0.3 * c.0 + 0.59 * c.1 + 0.11 * c.2 }
    static func clip(_ c: C) -> C {
        let l = lum(c), n = min(c.0, c.1, c.2), x = max(c.0, c.1, c.2)
        var r = c
        if n < 0 { r = (l + (r.0 - l) * l / (l - n), l + (r.1 - l) * l / (l - n), l + (r.2 - l) * l / (l - n)) }
        if x > 1 { r = (l + (r.0 - l) * (1 - l) / (x - l), l + (r.1 - l) * (1 - l) / (x - l), l + (r.2 - l) * (1 - l) / (x - l)) }
        return r
    }
    static func setLum(_ c: C, _ l: Double) -> C { let d = l - lum(c); return clip((c.0 + d, c.1 + d, c.2 + d)) }
    static func sat(_ c: C) -> Double { max(c.0, c.1, c.2) - min(c.0, c.1, c.2) }
    static func setSat(_ c: C, _ s: Double) -> C {
        var v = [c.0, c.1, c.2]
        let order = v.indices.sorted { v[$0] < v[$1] }
        let (lo, mid, hi) = (order[0], order[1], order[2])
        if v[hi] > v[lo] {
            v[mid] = (v[mid] - v[lo]) * s / (v[hi] - v[lo])
            v[hi] = s
        } else {
            v[mid] = 0; v[hi] = 0
        }
        v[lo] = 0
        return (v[0], v[1], v[2])
    }

    static func blend(_ mode: BlendMode, _ b: C, _ s: C) -> C {
        switch mode {
        case .hue: return setLum(setSat(s, sat(b)), lum(b))
        case .saturation: return setLum(setSat(b, sat(s)), lum(b))
        case .color: return setLum(s, lum(b))
        case .luminosity: return setLum(b, lum(s))
        default: return (separable(mode, b.0, s.0), separable(mode, b.1, s.1), separable(mode, b.2, s.2))
        }
    }
}

@Suite(.serialized) struct BlendRenderingTests {
    @Test func everyBlendModeMatchesFigmas() throws {
        let behind = RGBA(0.2, 0.4, 0.8), top = RGBA(0.8, 0.6, 0.2)
        var off: [String] = []
        for mode in BlendMode.allCases where mode != .normal {
            var over = shape(fill: top, at: Vec2(16, 16), size: Size2(32, 32))
            over.blendMode = mode
            let project = Project(composition: Composition(width: 64, height: 64, background: Background(color: .white)),
                                  layers: [shape(fill: behind, at: Vec2(0, 0), size: Size2(64, 64)), over])
            let p = pixel(try render(project), 32, 32)
            let want = BlendMaths.blend(mode, (behind.r, behind.g, behind.b), (top.r, top.g, top.b))
            let got = (Double(p.r) / 255, Double(p.g) / 255, Double(p.b) / 255)
            let error = max(abs(got.0 - want.0), abs(got.1 - want.1), abs(got.2 - want.2))
            // Core Animation's Soft Light is Pegtop's formula, a little
            // darker than the W3C's in dark colours (here 75 against 88 in
            // red), and Core Image's through Core Animation is further off.
            if error > (mode == .softLight ? 0.06 : 0.03) {
                off.append("\(mode.rawValue): got \(p.r),\(p.g),\(p.b) want \(Int(want.0 * 255)),\(Int(want.1 * 255)),\(Int(want.2 * 255))")
            }
        }
        #expect(off.isEmpty, "\(off.joined(separator: "; "))")
    }
}

@Suite(.serialized) struct ShadowRenderingTests {
    private func effects(_ layer: Layer, _ kinds: [EffectKind]) -> Layer {
        var l = layer
        l.effects = kinds.map { Effect(kind: $0) }
        return l
    }

    @Test func aShapeCastsEveryShadow() throws {
        let square = effects(shape(at: Vec2(22, 22), size: Size2(20, 20)), [
            .dropShadow(DropShadow(color: RGBA(0, 0, 1), offset: Vec2(10, 0), blur: 0, opacity: 1)),
            .dropShadow(DropShadow(color: RGBA(0, 1, 0), offset: Vec2(0, 10), blur: 0, opacity: 1)),
        ])
        let image = try render(Project(composition: transparentComposition(), layers: [square]))
        let right = pixel(image, 47, 30), below = pixel(image, 30, 47)
        #expect(right.b > 250 && right.a > 250, "the first shadow, to the right")
        #expect(below.g > 250 && below.a > 250, "the second, below")
        #expect(pixel(image, 47, 47).a == 0, "neither reaches the corner")
        #expect(pixel(image, 30, 30).r > 250, "the square over both")
    }

    @Test func aShadowNeverShowsThroughASeeThroughFill() throws {
        let glass = effects(shape(fill: RGBA(1, 0, 0, 0.5), at: Vec2(22, 22), size: Size2(20, 20)), [
            .dropShadow(DropShadow(color: .black, offset: Vec2(4, 4), blur: 0, opacity: 1)),
        ])
        let image = try render(Project(composition: transparentComposition(), layers: [glass]))
        let inside = pixel(image, 38, 38)
        #expect(inside.r > 250 && abs(inside.a - 128) < 8, "just the fill, with no shadow under it")
        let outside = pixel(image, 44, 44)
        #expect(outside.r < 5 && abs(outside.a - 128) < 12, "outside, as faint as the fill")
    }

    @Test func anInnerShadowFallsInsideTheWayItIsOffset() throws {
        let card = effects(shape(fill: .white, at: Vec2(12, 12), size: Size2(40, 40)), [
            .innerShadow(DropShadow(color: .black, offset: Vec2(0, 6), blur: 0, opacity: 1)),
        ])
        let image = try render(Project(composition: transparentComposition(), layers: [card]))
        let top = pixel(image, 32, 14), bottom = pixel(image, 32, 50)
        #expect(top.r < 5 && top.a > 250, "dark along the top edge, inside")
        #expect(bottom.r > 250, "the bottom stays white")
        #expect(pixel(image, 32, 8).a == 0, "nothing outside the shape")
    }

    @Test func anInnerShadowsSpreadFillsABandAllRound() throws {
        let card = effects(shape(fill: .white, at: Vec2(12, 12), size: Size2(40, 40)), [
            .innerShadow(DropShadow(color: RGBA(0, 0, 1), offset: .zero, blur: 0, opacity: 1, spread: 4)),
        ])
        let image = try render(Project(composition: transparentComposition(), layers: [card]))
        for (x, y) in [(14, 32), (50, 32), (32, 14), (32, 50)] {
            #expect(pixel(image, x, y).b > 250 && pixel(image, x, y).r < 5, "the band at \(x),\(y)")
        }
        #expect(pixel(image, 32, 32).r > 250, "the middle stays white")
    }

    @Test func aMaskPresetClipsWhatIsDrawn() throws {
        let square = shape(at: .zero, size: Size2(64, 64))
        var settings = PresetAction(preset: .maskResizeIn, direction: .left)
        settings.direction = .left
        let action = Action(target: square.id, start: 0, duration: 1, easing: .preset(.none, intensity: 0),
                            spec: .preset(settings))
        let project = Project(composition: transparentComposition(), layers: [square], actions: [action])
        // Halfway, the clip has opened across the left half.
        let half = try render(project, at: 0.5)
        #expect(pixel(half, 16, 32).a > 250)
        #expect(pixel(half, 48, 32).a == 0)
        // Before, nothing; after, the whole square, with no clip left behind.
        #expect(pixel(try render(project, at: 0), 16, 32).a == 0)
        #expect(pixel(try render(project, at: 1.1), 60, 60).a > 250)
    }

    @Test func lettersDrawOneByOne() throws {
        let content = TextContent(text: "II", fontFamily: "SF Pro", fontWeight: 900, fontSize: 40, color: RGBA(1, 0, 0))
        let size = TextLayout.size(of: content.text, style: TextStyle(content), width: nil)
        var layer = Layer(name: "T", content: .text(content), size: size, position: .zero)
        layer.transform.anchor = .zero
        var settings = PresetAction(preset: .fadeIn, unit: .letters, delay: 0.5)
        settings.unit = .letters
        let action = Action(target: layer.id, start: 0, duration: 1, easing: .preset(.none, intensity: 0),
                            spec: .preset(settings))
        let project = Project(composition: transparentComposition(), layers: [layer], actions: [action])
        let spans = TextSpans.spans(.letters, of: content.text, style: TextStyle(content), width: nil)
        func ink(_ image: CGImage, in box: Box) -> Int {
            var count = 0
            for x in Int(box.minX)..<Int(box.maxX) {
                for y in stride(from: Int(box.minY), to: Int(box.maxY), by: 2) where pixel(image, x, y).a > 128 { count += 1 }
            }
            return count
        }
        // Just before halfway the first letter is nearly in and the second
        // has not begun.
        let image = try render(project, at: 0.49)
        #expect(ink(image, in: spans[0].box) > 10)
        #expect(ink(image, in: spans[1].box) == 0)
        // Afterwards both show, drawn whole again.
        let after = try render(project, at: 1.1)
        #expect(ink(after, in: spans[1].box) > 10)
    }

    @Test func aMovingLineCarriesNothingOfItsNeighbours() throws {
        // Tall capitals and long tails, which reach into the margin round
        // the next line's picture.
        let content = TextContent(text: "Ag\nAg\nAg", fontFamily: "SF Pro", fontWeight: 900, fontSize: 24, color: RGBA(1, 0, 0))
        let size = TextLayout.size(of: content.text, style: TextStyle(content), width: nil)
        var layer = Layer(name: "T", content: .text(content), size: size, position: Vec2(8, 8))
        layer.transform.anchor = .zero
        // From the centre out: the middle line comes in first, alone.
        let settings = PresetAction(preset: .fadeIn, unit: .lines, order: .center, delay: 0.5)
        let action = Action(target: layer.id, start: 0, duration: 1, easing: .preset(.none, intensity: 0),
                            spec: .preset(settings))
        let project = Project(composition: transparentComposition(96), layers: [layer], actions: [action])
        let lines = TextSpans.spans(.lines, of: content.text, style: TextStyle(content), width: nil)
        #expect(lines.count == 3)
        let image = try render(project, pixels: 96, at: 0.49)
        func ink(rows: ClosedRange<Double>) -> Int {
            var count = 0
            for y in Int(8 + rows.lowerBound)...Int(8 + rows.upperBound) {
                for x in 0..<96 where pixel(image, x, y).a > 40 { count += 1 }
            }
            return count
        }
        // The middle line shows; above and below it nothing has begun, so
        // nothing of the other lines rides along with it.
        #expect(ink(rows: lines[1].box.minY + 4...lines[1].box.maxY - 4) > 20)
        #expect(ink(rows: 0...lines[0].box.maxY - 3) == 0)
        #expect(ink(rows: lines[2].box.minY + 3...lines[2].box.maxY) == 0)
    }

    @Test func aTextStrokeOutlinesTheLetters() throws {
        var content = TextContent(text: "I", fontFamily: "SF Pro", fontWeight: 900, fontSize: 48, color: RGBA(1, 0, 0))
        let size = TextLayout.size(of: content.text, style: TextStyle(content), width: nil)
        func layer(_ c: TextContent) -> Layer {
            var l = Layer(name: "T", content: .text(c), size: size, position: Vec2(20, 4))
            l.transform.anchor = .zero
            return l
        }
        // Where the letter's stem is, filled: the inked columns across its middle.
        let filled = try render(Project(composition: transparentComposition(), layers: [layer(content)]))
        let row = Int(4 + size.height / 2)
        let inked = (0..<64).filter { pixel(filled, $0, row).a > 200 }
        let left = try #require(inked.first), right = try #require(inked.last)
        let middle = (left + right) / 2
        // The fill off and a stroke outside: a ring round the stem, empty inside.
        content.hidesFill = true
        content.stroke = Stroke(paint: .color(RGBA(0, 0, 1)), width: 3, alignment: .outside)
        let outlined = try render(Project(composition: transparentComposition(), layers: [layer(content)]))
        #expect(pixel(outlined, middle, row).a == 0)
        #expect(pixel(outlined, left - 2, row).b > 200 && pixel(outlined, left - 2, row).a > 200)
        #expect(pixel(outlined, right + 2, row).a > 200)
        // Saved and read back as it was; a shown fill leaves nothing in the file.
        let data = try JSONEncoder().encode(content)
        #expect(try JSONDecoder().decode(TextContent.self, from: data) == content)
        content.hidesFill = nil
        #expect(!(String(data: try JSONEncoder().encode(content), encoding: .utf8) ?? "").contains("hidesFill"))
    }
}
