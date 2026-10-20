import Foundation
import QuartzCore
import CoreGraphics
import MotionModel
import MotionEvaluation

/// Figma's Glass, drawn with the pieces macOS builds its own Liquid Glass
/// from, none of them in the public headers (the spike of 19 October 2026):
///
/// - a `CABackdropLayer` shows what is behind the layer, as background blur
///   does, through Core Animation's `displacementMap` filter (Refraction);
///   over it a second backdrop shows that, through `chromaticAberrationMap`
///   (Dispersion) and `gaussianBlur` (Frost). Both map filters read a
///   sublayer of their backdrop named `glassField`. Two backdrops, because
///   a map filter after another filter on one backdrop reads its map out of
///   place: the colours split in a band along the top and bottom edges and
///   the bend fell away;
/// - that sublayer is a `CASDFLayer`: a distance field of the outline, from
///   one `CASDFElementLayer`, run through a `CASDFGlassDisplacementEffect`
///   whose `height` is how far in the bend reaches (Depth) and whose
///   `curvature` how it spreads towards the middle (Splay);
/// - over the fills, two more distance-field layers with a
///   `CASDFGlassHighlightEffect` each light the rim from Figma's angle and,
///   more softly, from the opposite side (Light).
///
/// An element in its own `bounds` mode is a box with every corner rounded
/// alike, exact and free, which most glass is. Any other outline is a
/// picture (`contents` mode, `GlassField`): red is the signed distance, from
/// `contentsZeroValueDistance` to `contentsOneValueDistance`, green and blue
/// which way the edge lies (0.5 plus half the unit direction); the picture
/// must be tagged sRGB, or its values are converted and the edge moves in.
/// The field only exists inside the element's frame, so the backdrops, the
/// fields and the elements reach `margin` past the box: cut off at the edge,
/// the bend went one-sided. A field no filter reads draws itself, and one
/// hidden bends nothing, so each is shown exactly while read. All of it
/// draws the same on the canvas and in `CARenderer`, except that the field's
/// picture runs upside down off screen (`flipsContents`). If any piece is
/// missing, the glass is drawn as its frost alone.
enum GlassKit {
    static let backdrop = NSClassFromString("CABackdropLayer") as? CALayer.Type
    static let field = NSClassFromString("CASDFLayer") as? CALayer.Type
    static let element = NSClassFromString("CASDFElementLayer") as? CALayer.Type
    static let bend = NSClassFromString("CASDFGlassDisplacementEffect") as? NSObject.Type
    static let light = NSClassFromString("CASDFGlassHighlightEffect") as? NSObject.Type

    /// Whether everything that bends is there.
    static let bends: Bool = field != nil && element != nil && bend != nil && light != nil
        && PrivateFilter.make("displacementMap") != nil && PrivateFilter.make("chromaticAberrationMap") != nil

    /// The name the backdrops' filters find their field by.
    static let fieldName = "glassField"

    /// How far past the box the glass works, for a glass of `depth` and
    /// `frost` (already `fitted`): the field reaches a little past the bend,
    /// and the frost blurs in from at most 64 points out. On screen a
    /// backdrop shows whatever is on the screen where it lies, the desktop,
    /// the Dock and the menu bar included, so it is kept no bigger than
    /// the glass needs.
    static func margin(_ glass: Glass) -> CGFloat {
        CGFloat((glass.depth + min(glass.frost * 1.5, 64) + 8).rounded(.up))
    }

    /// `glass` on a box of `size`: its depth reaches at most to the middle
    /// of the shorter side, as a lens that size could. Deeper, the bend
    /// pulled what was hundreds of points away into the shape, past the
    /// window too (Depth 639 on a 248 point circle, 20 October 2026: the
    /// middle turned inside out and the screen around Twine showed in it).
    static func fitted(_ glass: Glass, to size: Size2) -> Glass {
        var g = glass
        g.depth = min(g.depth, max(min(size.width, size.height), 0) / 2)
        return g
    }

    /// Pixels the edge moves what is behind it at full refraction, and the
    /// colours part at full dispersion, for each pixel of depth.
    static let refractionPerDepth = 1.0
    static let dispersionPerDepth = 0.5
    /// The opposite rim's light, as a share of the lit one's, and how far
    /// round the rim each reaches, in radians.
    static let oppositeLight = 0.6
    static let lightSpread = Double.pi * 2 / 3
}

/// One backdrop of a glass, clipped to the outline, with its field.
private final class GlassStage {
    let backdrop: CALayer
    let mask = CAShapeLayer()
    let field: CALayer?
    let element: CALayer?

    init(_ kind: CALayer.Type, bends: Bool) {
        backdrop = kind.init()
        backdrop.mask = mask
        mask.fillColor = CGColor(gray: 0, alpha: 1)
        if bends, let fieldKind = GlassKit.field, let elementKind = GlassKit.element {
            let field = fieldKind.init(), element = elementKind.init()
            field.name = GlassKit.fieldName
            field.addSublayer(element)
            backdrop.addSublayer(field)
            self.field = field
            self.element = element
        } else {
            field = nil
            element = nil
        }
        for l in [backdrop, mask, field, element].compactMap({ $0 }) {
            l.anchorPoint = .zero
            l.actions = Node.noActions
        }
    }

    /// Placed over `whole`, clipped to `outline`, filtering by `filters`;
    /// shown only when it has any, its field only when one reads it.
    func set(whole: CGRect, outline: CGPath, filters: [Any], readsField: Bool) {
        backdrop.isHidden = filters.isEmpty
        backdrop.frame = whole
        mask.frame = backdrop.bounds
        mask.path = outline
        backdrop.filters = filters
        field?.frame = backdrop.bounds
        field?.isHidden = !readsField
    }
}

/// The layers a shape's or frame's glass is drawn with: `backdrops` under
/// the fills, `lights` over them (and over the inner shadows).
final class GlassLayers {
    let backdrops: [CALayer]
    private(set) var lights: [CALayer] = []
    private let bendStage: GlassStage
    private let splitStage: GlassStage
    private var lightElements: [CALayer] = []
    private var drawn: (glass: Glass, shape: ResolvedShape, size: Size2, flips: Bool, texels: Double)?
    private var picture: (path: CGPath, size: CGSize, range: Double, flips: Bool, texels: Double, image: CGImage?)?

    /// Nil when the system has no backdrop layer.
    init?() {
        guard let kind = GlassKit.backdrop else { return nil }
        bendStage = GlassStage(kind, bends: GlassKit.bends)
        splitStage = GlassStage(kind, bends: GlassKit.bends)
        backdrops = [bendStage.backdrop, splitStage.backdrop]
        guard GlassKit.bends, let fieldKind = GlassKit.field, let elementKind = GlassKit.element else { return }
        for _ in 0..<2 {
            let light = fieldKind.init()
            let element = elementKind.init()
            light.addSublayer(element)
            lights.append(light)
            lightElements.append(element)
        }
        for l in lights + lightElements {
            l.anchorPoint = .zero
            l.actions = Node.noActions
        }
    }

    /// Draws `glass` on `shape` (in a box of `size`), whose plain area is
    /// `area`, shown at `pixelScale` pixels a point (the canvas's zoom
    /// included). Does nothing when nothing changed.
    func update(_ glass: Glass, shape: ResolvedShape, area: CGPath, size: Size2, flips: Bool, pixelScale: CGFloat) {
        // Rounded up to a power of two, so a pinch draws the field picture
        // again only as the zoom doubles, not every frame; a rounded box
        // needs no picture, so the zoom never touches it.
        let texels = shape.roundedBox != nil ? 1 : pow(2, log2(Double(max(pixelScale, 1))).rounded(.up))
        if let drawn, drawn.glass == glass, drawn.shape == shape, drawn.size == size, drawn.flips == flips,
           drawn.texels == texels { return }
        drawn = (glass, shape, size, flips, texels)
        let glass = GlassKit.fitted(glass, to: size)
        let m = GlassKit.margin(glass)
        let box = CGRect(x: 0, y: 0, width: max(size.width, 0), height: max(size.height, 0))
        let whole = box.insetBy(dx: -m, dy: -m)
        var shift = CGAffineTransform(translationX: m, y: m)
        let outline = area.copy(using: &shift) ?? area
        let frost: [Any] = glass.frost > 0 ? [Blur.filter(amount: glass.frost)] : []
        guard GlassKit.bends, let bendKind = GlassKit.bend, let lightKind = GlassKit.light,
              let bendElement = bendStage.element, let splitElement = splitStage.element else {
            bendStage.set(whole: whole, outline: outline, filters: [], readsField: false)
            splitStage.set(whole: whole, outline: outline, filters: frost, readsField: false)
            return
        }

        // The outline as a distance field, for the bend and the light alike.
        let range = glass.depth + 4
        let elements = [bendElement, splitElement] + lightElements
        if let radius = shape.roundedBox {
            for e in elements {
                e.setValue("bounds", forKey: "mode")
                e.contents = nil
                e.frame = box.offsetBy(dx: m, dy: m)
                e.cornerRadius = radius
            }
        } else {
            let image = fieldPicture(outline, size: whole.size, range: range, flips: flips, texels: texels)
            for e in elements {
                e.setValue("contents", forKey: "mode")
                e.cornerRadius = 0
                e.frame = CGRect(origin: .zero, size: whole.size)
                e.contents = image
                e.setValue(-range, forKey: "contentsZeroValueDistance")
                e.setValue(range, forKey: "contentsOneValueDistance")
            }
        }
        for field in [bendStage.field, splitStage.field].compactMap({ $0 }) {
            let bend = bendKind.init()
            bend.setValue(glass.depth, forKey: "height")
            bend.setValue(1 + 3 * glass.splay, forKey: "curvature")
            field.setValue(bend, forKey: "effect")
        }

        let bends = glass.depth > 0 && glass.refraction > 0
        let refraction = bends ? PrivateFilter.make("displacementMap") : nil
        refraction?.setValue(GlassKit.fieldName, forKey: "inputSourceSublayerName")
        refraction?.setValue(glass.refraction * glass.depth * GlassKit.refractionPerDepth, forKey: "inputAmount")
        bendStage.set(whole: whole, outline: outline, filters: refraction.map { [$0] } ?? [], readsField: refraction != nil)

        let splits = glass.depth > 0 && glass.dispersion > 0
        let dispersion = splits ? PrivateFilter.make("chromaticAberrationMap") : nil
        dispersion?.setValue(GlassKit.fieldName, forKey: "inputSourceSublayerName")
        dispersion?.setValue(glass.dispersion * glass.depth * GlassKit.dispersionPerDepth, forKey: "inputAmount")
        splitStage.set(whole: whole, outline: outline, filters: (dispersion.map { [$0] } ?? []) + frost,
                       readsField: dispersion != nil)

        // Figma's dial: 0 at the top, -45 the top left, the same on the
        // canvas and off screen.
        for (i, light) in lights.enumerated() {
            light.frame = whole
            let effect = lightKind.init()
            effect.setValue(CGColor(gray: 1, alpha: 1), forKey: "color")
            effect.setValue((glass.lightAngle + (i == 0 ? 0 : 180)) * .pi / 180, forKey: "angle")
            effect.setValue(glass.lightIntensity * (i == 0 ? 1 : GlassKit.oppositeLight), forKey: "amount")
            effect.setValue(min(max(glass.depth / 6, 1.5), 4), forKey: "height")
            effect.setValue(GlassKit.lightSpread, forKey: "spread")
            effect.setValue(1.0, forKey: "curvature")
            light.setValue(effect, forKey: "effect")
            light.isHidden = glass.lightIntensity <= 0
        }
    }

    private func fieldPicture(_ path: CGPath, size: CGSize, range: Double, flips: Bool, texels: Double) -> CGImage? {
        if let picture, picture.path == path, picture.size == size, picture.range == range, picture.flips == flips,
           picture.texels == texels {
            return picture.image
        }
        let image = GlassField.picture(of: path, size: size, range: range, flips: flips, texelsPerPoint: texels)
        picture = (path, size, range, flips, texels, image)
        return image
    }
}

/// The distance field of an outline as a picture a `CASDFElementLayer`
/// reads in its `contents` mode (see `GlassKit`).
enum GlassField {
    /// The longest side a field picture is worked out at; bigger outlines
    /// are worked out coarser, which a distance field takes well.
    static let largestSide = 2048

    /// `path` (in points, y down, inside `size`) as signed distances held to
    /// `range` either way, negative inside, and the way to the edge, with
    /// `texelsPerPoint` across each point it shows at: stretched, a coarse
    /// field bends in blotches, which the canvas zoomed in on a small star
    /// showed.
    static func picture(of path: CGPath, size: CGSize, range: Double, flips: Bool, texelsPerPoint: Double = 1) -> CGImage? {
        guard size.width >= 1, size.height >= 1, range > 0 else { return nil }
        let step = max(1 / max(texelsPerPoint, 1), Double(max(size.width, size.height)) / Double(largestSide))
        let w = Int((Double(size.width) / step).rounded(.up)), h = Int((Double(size.height) / step).rounded(.up))
        var toTexels = CGAffineTransform(scaleX: 1 / step, y: 1 / step)
        guard let scaled = path.copy(using: &toTexels) else { return nil }

        // Inside or out, from the outline filled, row 0 at the top.
        guard let fill = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
              let coverage = fill.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        fill.translateBy(x: 0, y: CGFloat(h))
        fill.scaleBy(x: 1, y: -1)
        fill.addPath(scaled)
        fill.setFillColor(gray: 1, alpha: 1)
        fill.fillPath()

        let segments = Self.segments(of: scaled)
        let reach = range / step
        let cell = max(reach, 4)
        let columns = Int((Double(w) / cell).rounded(.up)) + 1, rows = Int((Double(h) / cell).rounded(.up)) + 1
        var buckets = [[Int32]](repeating: [], count: columns * rows)
        for (i, s) in segments.enumerated() {
            let x0 = max(0, Int((min(s.a.x, s.b.x) - reach) / cell)), x1 = min(columns - 1, Int((max(s.a.x, s.b.x) + reach) / cell))
            let y0 = max(0, Int((min(s.a.y, s.b.y) - reach) / cell)), y1 = min(rows - 1, Int((max(s.a.y, s.b.y) + reach) / cell))
            guard x0 <= x1, y0 <= y1 else { continue }
            for y in y0...y1 { for x in x0...x1 { buckets[y * columns + x].append(Int32(i)) } }
        }

        var pixels = [UInt16](repeating: 0, count: w * h * 4)
        let reach2 = reach * reach
        for y in 0..<h {
            let row = flips ? h - 1 - y : y
            for x in 0..<w {
                let px = Double(x) + 0.5, py = Double(y) + 0.5
                let inside = coverage[y * w + x] >= 128
                var best = reach2, nx = 0.0, ny = 0.0
                for i in buckets[min(Int(py / cell), rows - 1) * columns + min(Int(px / cell), columns - 1)] {
                    let s = segments[Int(i)]
                    let dx = s.b.x - s.a.x, dy = s.b.y - s.a.y, length2 = dx * dx + dy * dy
                    var t = length2 > 0 ? ((px - s.a.x) * dx + (py - s.a.y) * dy) / length2 : 0
                    t = min(max(t, 0), 1)
                    let ex = px - (s.a.x + t * dx), ey = py - (s.a.y + t * dy)
                    let d2 = ex * ex + ey * ey
                    if d2 < best { best = d2; nx = ex; ny = ey }
                }
                var distance = range, gx = 0.0, gy = 0.0
                if best < reach2 {
                    let d = best.squareRoot()
                    distance = d * step
                    if d > 1e-6 { gx = nx / d; gy = ny / d }
                }
                // The field grows outward: inside, the way out is towards the
                // nearest edge.
                if inside { distance = -distance; gx = -gx; gy = -gy }
                if flips { gy = -gy }
                let o = (row * w + x) * 4
                pixels[o] = UInt16(min(max((distance + range) / (2 * range), 0), 1) * 65535)
                pixels[o + 1] = UInt16(min(max(0.5 + 0.5 * gx, 0), 1) * 65535)
                pixels[o + 2] = UInt16(min(max(0.5 + 0.5 * gy, 0), 1) * 65535)
                pixels[o + 3] = 65535
            }
        }
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes: pixels, count: pixels.count * 2) as CFData) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: w * 8, space: srgb,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder16Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    struct Segment { var a: (x: Double, y: Double); var b: (x: Double, y: Double) }

    /// The outline as straight pieces, curves cut by their length.
    static func segments(of path: CGPath) -> [Segment] {
        var segments: [Segment] = []
        var start = (x: 0.0, y: 0.0), last = start
        func line(to p: (x: Double, y: Double)) {
            segments.append(Segment(a: last, b: p))
            last = p
        }
        func pieces(_ length: Double) -> Int { min(max(Int((length / 2).rounded(.up)), 2), 64) }
        path.applyWithBlock { element in
            let p = element.pointee.points
            func at(_ i: Int) -> (x: Double, y: Double) { (Double(p[i].x), Double(p[i].y)) }
            switch element.pointee.type {
            case .moveToPoint:
                start = at(0); last = start
            case .addLineToPoint:
                line(to: at(0))
            case .addQuadCurveToPoint:
                let a = last, c = at(0), b = at(1)
                let n = pieces(hypot(c.x - a.x, c.y - a.y) + hypot(b.x - c.x, b.y - c.y))
                for k in 1...n {
                    let t = Double(k) / Double(n), u = 1 - t
                    line(to: (u * u * a.x + 2 * u * t * c.x + t * t * b.x, u * u * a.y + 2 * u * t * c.y + t * t * b.y))
                }
            case .addCurveToPoint:
                let a = last, c1 = at(0), c2 = at(1), b = at(2)
                let n = pieces(hypot(c1.x - a.x, c1.y - a.y) + hypot(c2.x - c1.x, c2.y - c1.y) + hypot(b.x - c2.x, b.y - c2.y))
                for k in 1...n {
                    let t = Double(k) / Double(n), u = 1 - t
                    let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
                    line(to: (w0 * a.x + w1 * c1.x + w2 * c2.x + w3 * b.x, w0 * a.y + w1 * c1.y + w2 * c2.y + w3 * b.y))
                }
            case .closeSubpath:
                if last != start { line(to: start) }
            @unknown default:
                break
            }
        }
        return segments
    }
}
