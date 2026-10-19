import Foundation
import AppKit
import CryptoKit
import MotionModel
import MotionEvaluation
import MotionEditing

/// What the Twine plugin for Figma copies: the selected layers, described as
/// Twine can build them, with every picture they use.
///
/// The plugin decides what Twine cannot hold and sends that part already
/// flattened, as a picture Figma drew (`picture`) or as Figma's own SVG of it
/// (`svg`); everything else comes as plain values in Figma's terms. Each
/// layer's transform is its absolute one in Figma, so groups, whose
/// children Figma measures from the frame around them, need no special care.
public struct FigmaPayload: Codable, Sendable {
    /// Always `twine.figma`: how Twine knows the clipboard holds one.
    public var format: String
    public var version: Int
    public var nodes: [Node]
    /// Picture fills' bytes, base64, by Figma's image hash.
    public var images: [String: String]
    /// What the plugin had to leave out, in words, to show.
    public var warnings: [String]?

    public static let formatName = "twine.figma"

    public struct Node: Codable, Sendable {
        public var kind: String
        public var name: String
        public var visible: Bool?
        public var locked: Bool?
        public var opacity: Double?
        public var blend: String?
        /// Figma's absolute transform as `a b c d tx ty`: x' = a·x + c·y + tx.
        public var transform: [Double]
        public var width: Double
        public var height: Double
        public var fills: [Paint]?
        public var strokes: [Paint]?
        public var strokeWeight: Double?
        public var strokeAlign: String?
        public var dash: [Double]?
        public var cap: String?
        public var join: String?
        /// Top-left, top-right, bottom-right, bottom-left.
        public var radii: [Double]?
        public var effects: [Effect]?
        public var clips: Bool?
        public var isMask: Bool?
        public var maskType: String?
        public var children: [Node]?
        /// Ellipses: Figma's arc, in radians clockwise from three o'clock.
        public var arc: Arc?
        /// Polygons' sides and stars' points; stars' inner radius as a
        /// fraction.
        public var count: Int?
        public var inner: Double?
        /// Vectors: their outlines in their own space.
        public var paths: [PathData]?
        /// Vectors: their rounded points as `x y radius`, in their own
        /// space. Figma keeps these on its vector network; the outlines
        /// are sharp.
        public var corners: [[Double]]?
        public var text: Text?
        /// Pictures: Figma's drawing, and its box in the page.
        public var png: String?
        public var svg: String?
        public var bounds: [Double]?
    }

    public struct Paint: Codable, Sendable {
        public var type: String
        public var visible: Bool?
        public var opacity: Double?
        public var color: Color?
        public var stops: [Stop]?
        /// Gradients: `a b c d tx ty`, from the layer's box (0 to 1) into
        /// the gradient's own space.
        public var transform: [Double]?
        public var image: String?
        public var scaleMode: String?
        public var imageTransform: [Double]?
        public var scalingFactor: Double?
        public var rotation: Double?
    }

    public struct Color: Codable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double
        public var a: Double?
    }

    public struct Stop: Codable, Sendable {
        public var position: Double
        public var color: Color
    }

    public struct Effect: Codable, Sendable {
        public var type: String
        public var visible: Bool?
        public var color: Color?
        public var offset: Offset?
        public var radius: Double?
        public var spread: Double?
        /// Glass only: Figma's own numbers, its frost being `radius`.
        public var lightIntensity: Double?
        public var lightAngle: Double?
        public var refraction: Double?
        public var depth: Double?
        public var dispersion: Double?
        public var splay: Double?
    }

    public struct Offset: Codable, Sendable {
        public var x: Double
        public var y: Double
    }

    public struct Arc: Codable, Sendable {
        public var start: Double
        public var end: Double
        public var inner: Double
    }

    public struct PathData: Codable, Sendable {
        public var rule: String
        public var d: String
    }

    public struct Text: Codable, Sendable {
        public var characters: String
        public var family: String
        public var style: String
        public var size: Double
        public var letterSpacing: Double?
        public var lineHeight: Double?
        public var align: String?
        public var autoResize: String?
    }
}

/// The plugin's copy made into Twine layers.
public enum FigmaImport {
    /// The most sides or points a pasted polygon or star keeps, as many as
    /// the inspector offers.
    static let maxPoints = 60

    public struct Result: Sendable {
        /// The selected layers, back to front, placed in Figma's page space.
        public var layers: [Layer]
        /// The box around them in that space.
        public var bounds: Box
        public var media: [SVGImport.EmbeddedMedia]
        /// Fonts the text uses that this Mac does not have, shown in a
        /// stand-in until they are installed.
        public var missingFonts: [String]
        /// What the plugin left out, in words.
        public var warnings: [String]
    }

    public enum ReadError: Error, Equatable {
        case notAPayload, newerVersion, empty
        /// Its SVG parts together need more drawing than any paste should.
        case tooComplex
    }

    /// Whether `text` is a copy from the plugin, without reading it all.
    public static func isPayload(_ text: String) -> Bool {
        text.prefix(80).contains("\"\(FigmaPayload.formatName)\"")
    }

    /// `budget` is what the paste's SVG parts may have the system draw,
    /// together.
    public static func read(_ text: String, budget: SVGImport.Budget = SVGImport.Budget()) throws -> Result {
        // Any app can put text on the clipboard, so its numbers are held in
        // range as a project file's are, before and after building.
        guard isPayload(text),
              let payload = try? JSONDecoder().decode(FigmaPayload.self, from: FileSafety.numbersHeld(Data(text.utf8))),
              payload.format == FigmaPayload.formatName else { throw ReadError.notAPayload }
        guard payload.version <= 1 else { throw ReadError.newerVersion }
        var builder = FigmaBuilder(images: payload.images, budget: budget)
        let layers = FileSafety.held(Finite.layers(builder.layers(payload.nodes, parent: .identity)))
        guard !builder.tooComplex else { throw ReadError.tooComplex }
        let boxes = layers.compactMap(Arrangement.box(of:))
        guard let first = boxes.first else { throw ReadError.empty }
        return Result(layers: layers, bounds: boxes.dropFirst().reduce(first) { $0.union($1) },
                      media: builder.media, missingFonts: builder.missingFonts.sorted(), warnings: payload.warnings ?? [])
    }
}

// MARK: - Building

private struct FigmaBuilder {
    let images: [String: String]
    var media: [SVGImport.EmbeddedMedia] = []
    /// Figma image hashes already added, by the id Twine gave them.
    private var added: [String: UUID] = [:]
    private(set) var missingFonts: Set<String> = []
    /// What every SVG in the paste may have drawn by the system, together.
    private let budget: SVGImport.Budget
    /// Set when an SVG was past the budget or its own limits.
    private(set) var tooComplex = false

    init(images: [String: String], budget: SVGImport.Budget) {
        self.images = images
        self.budget = budget
    }

    /// Siblings, back to front. A mask masks every sibling in front of it
    /// until the next mask, in Figma and Twine alike, so it comes in as it
    /// is. A group or frame Twine cannot draw as a mask comes in as itself.
    mutating func layers(_ nodes: [FigmaPayload.Node], parent: Affine) -> [Layer] {
        var out: [Layer] = []
        for node in nodes {
            guard var layer = self.layer(node, parent: parent) else { continue }
            if node.isMask == true, layer.canMask {
                if node.maskType == "VECTOR", var look = layer.look {
                    // An outline mask ignores how see-through its fill is.
                    look.fills = [Fill(paint: .color(.black))]
                    layer.look = look
                }
                layer.isMask = true
            }
            out.append(layer)
        }
        return out
    }

    private static func affine(_ v: [Double]) -> Affine {
        guard v.count == 6 else { return .identity }
        return Affine(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
    }

    mutating func layer(_ node: FigmaPayload.Node, parent: Affine) -> Layer? {
        let absolute = Self.affine(node.transform)
        let intoParent = parent.inverted ?? .identity
        let size = Size2(max(node.width, 0), max(node.height, 0))
        var layer: Layer
        // Where the layer's box starts in the space Figma measures it in:
        // the origin, except for a vector, whose outline sets its box.
        var origin = Vec2.zero
        switch node.kind {
        case "frame", "group":
            let children = layers(node.children ?? [], parent: absolute)
            if node.kind == "frame" {
                var frame = LayerFactory.frame(in: Box(origin: .zero, size: size), name: node.name)
                if case .group(var g) = frame.content {
                    var look = fills(node)
                    let corners = radii(node)
                    // Children are stored back to front: the picture goes behind them all.
                    g.children = (background(of: &look, size: size, radii: corners).map { [$0] } ?? []) + children
                    g.clipsContent = node.clips ?? false
                    g.frame = FrameStyle(fills: look, strokes: strokes(node, closed: true), cornerRadii: corners)
                    frame.content = .group(g)
                }
                layer = frame
            } else {
                layer = LayerFactory.group(in: Box(origin: .zero, size: size), children: children, name: node.name)
            }
        case "rectangle":
            layer = shape(.rectangle(cornerRadii: radii(node)), node, size: size, closed: true)
        case "ellipse":
            let arc = node.arc.map { EllipseArc(start: $0.start * 180 / .pi, end: $0.end * 180 / .pi, innerRadius: $0.inner) } ?? .full
            layer = shape(.ellipse(arc: arc.isWhole && arc.innerRadius == 0 ? .full : arc), node, size: size, closed: true)
        case "polygon":
            layer = shape(.polygon(sides: min(max(node.count ?? 3, 3), FigmaImport.maxPoints), cornerRadius: max(node.radii?.first ?? 0, 0)),
                          node, size: size, closed: true)
        case "star":
            layer = shape(.star(points: min(max(node.count ?? 5, 3), FigmaImport.maxPoints), innerRadius: node.inner ?? 0.4,
                                cornerRadius: node.radii?.first ?? 0), node, size: size, closed: true)
        case "line":
            layer = shape(.line, node, size: Size2(size.width, 0), closed: false)
        case "vector":
            guard let made = vector(node) else { return nil }
            (layer, origin) = made
        case "text":
            guard let made = text(node, size: size) else { return nil }
            layer = made
        case "picture":
            return picture(node, into: intoParent)
        case "svg":
            return svgLayer(node, into: intoParent)
        default:
            return nil
        }

        // Where the layer sits: its box's centre, turned and (for a mirrored
        // layer) flipped as Figma has it, in its parent's space.
        let local = absolute.then(intoParent)
        place(&layer, local: local, box: Box(origin: origin, size: layer.size))
        layer.name = node.name
        layer.isVisible = node.visible ?? true
        layer.isLocked = node.locked ?? false
        layer.opacity = min(max(node.opacity ?? 1, 0), 1)
        layer.blendMode = Self.blend(node.blend)
        layer.effects = (node.effects ?? []).compactMap(Self.effect)
        return layer
    }

    /// A layer placed so its box, in its own space, lands where `local` puts
    /// it: the anchor at the box's centre. Any matrix is a rotation of a
    /// skew of a scale, which is Twine's order, so a skewed layer lands
    /// exactly: what the turn and the two scales leave is a skew across.
    private func place(_ layer: inout Layer, local: Affine, box: Box) {
        let sx = hypot(local.a, local.b)
        let det = local.determinant
        layer.transform.anchor = Vec2(layer.size.width / 2, layer.size.height / 2)
        layer.transform.rotation = atan2(local.b, local.a) * 180 / .pi
        // Figma's layers do not scale; a mirrored one flips on its height.
        let sy = sx > 1e-9 ? det / sx : 1
        layer.transform.scale = Vec2(sx, sy)
        layer.transform.isScaleLinked = abs(sx - abs(sy)) < 1e-9
        // The second column, turned back, is (tan(skew) · sy, sy).
        let slant = abs(det) > 1e-12 ? (local.a * local.c + local.b * local.d) / det : 0
        let skew = atan(slant) * 180 / .pi
        layer.transform.skew = Vec2(abs(skew) < 1e-6 ? 0 : skew, 0)
        layer.transform.position = local.apply(box.center)
    }

    // MARK: Shapes

    private mutating func shape(_ geometry: ShapeGeometry, _ node: FigmaPayload.Node, size: Size2, closed: Bool) -> Layer {
        let content = ShapeContent(geometry: geometry, fills: closed ? fills(node) : [], strokes: strokes(node, closed: closed))
        return Layer(name: node.name, content: .shape(content), size: size, position: .zero)
    }

    /// A vector's outlines, fitted to their own box, which becomes the
    /// layer's, with where that box starts in the vector's own space.
    private mutating func vector(_ node: FigmaPayload.Node) -> (Layer, Vec2)? {
        let parts = node.paths ?? []
        var subpaths: [Subpath] = []
        for part in parts { subpaths += SVGPathData.parse(part.d).subpaths }
        let path = Self.rounding(BezierPath(subpaths: subpaths), at: node.corners ?? [])
        guard let bounds = path.bounds else { return nil }
        let local = path.transformed(by: .translation(Vec2(-bounds.minX, -bounds.minY)))
        let closed = subpaths.allSatisfy(\.isClosed)
        var content = ShapeContent(geometry: .path(local), fills: fills(node), strokes: strokes(node, closed: closed))
        content.fillRule = !parts.isEmpty && parts.allSatisfy({ $0.rule == "EVENODD" }) ? .evenOdd : .nonZero
        let layer = Layer(name: node.name, content: .shape(content), size: Size2(bounds.width, bounds.height), position: .zero)
        return (layer, Vec2(bounds.minX, bounds.minY))
    }

    /// Each point of `path` at one of `corners`' places takes its radius.
    static func rounding(_ path: BezierPath, at corners: [[Double]]) -> BezierPath {
        let rounded = corners.filter { $0.count == 3 && $0[2] > 0 }
        guard !rounded.isEmpty else { return path }
        var path = path
        for s in path.subpaths.indices {
            for i in path.subpaths[s].points.indices {
                let p = path.subpaths[s].points[i].position
                if let corner = rounded.first(where: { abs($0[0] - p.x) < 0.01 && abs($0[1] - p.y) < 0.01 }) {
                    path.subpaths[s].points[i].cornerRadius = corner[2]
                }
            }
        }
        return path
    }

    private func radii(_ node: FigmaPayload.Node) -> CornerRadii {
        guard let r = node.radii, r.count == 4 else { return CornerRadii(all: node.radii?.first ?? 0) }
        return CornerRadii(topLeft: r[0], topRight: r[1], bottomRight: r[2], bottomLeft: r[3])
    }

    // MARK: Paints

    /// A layer's fills, bottom first, with one picture at most: the topmost
    /// shown (or the topmost, when none is). Pictures stacked under it cannot
    /// be seen through it, so they are left out, as the plugin leaves them out
    /// of the copy.
    private mutating func fills(_ node: FigmaPayload.Node) -> [Fill] {
        let paints = node.fills ?? []
        let top = paints.lastIndex { $0.type == "IMAGE" && $0.visible != false } ?? paints.lastIndex { $0.type == "IMAGE" }
        return paints.enumerated().compactMap { i, paint in
            guard paint.type != "IMAGE" || i == top else { return nil }
            return self.paint(paint, size: Size2(node.width, node.height)).map { Fill(isEnabled: paint.visible ?? true, paint: $0) }
        }
    }

    /// A frame's picture background as a layer of its own, at the bottom of
    /// the frame, the frame's size and corners, so it shows in the layers
    /// panel and can be picked, replaced and animated. Fills Figma drew over
    /// the picture (a tint) go with it; those under it stay the frame's.
    /// Nil, and the fills unchanged, when the frame has no picture.
    private func background(of fills: inout [Fill], size: Size2, radii: CornerRadii) -> Layer? {
        guard let i = fills.lastIndex(where: { $0.paint.isImage }) else { return nil }
        let lifted = Array(fills[i...])
        fills.removeSubrange(i...)
        var layer = Layer(name: "Background", content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: radii), fills: lifted)),
                          size: size, position: Vec2(size.width / 2, size.height / 2))
        layer.transform.anchor = Vec2(size.width / 2, size.height / 2)
        return layer
    }

    private mutating func strokes(_ node: FigmaPayload.Node, closed: Bool) -> [Stroke] {
        guard let weight = node.strokeWeight, weight > 0 else { return [] }
        return (node.strokes ?? []).compactMap { paint in
            guard let p = self.paint(paint, size: Size2(node.width, node.height)), !p.isImage else { return nil }
            var stroke = Stroke(isEnabled: paint.visible ?? true, paint: p, width: weight)
            if closed { stroke.alignment = node.strokeAlign == "INSIDE" ? .inside : node.strokeAlign == "OUTSIDE" ? .outside : .center }
            stroke.cap = node.cap == "ROUND" ? .round : node.cap == "SQUARE" ? .square : .butt
            stroke.join = node.join == "ROUND" ? .round : node.join == "BEVEL" ? .bevel : .miter
            if let dash = node.dash, dash.contains(where: { $0 > 0 }) { stroke.dashPattern = dash.count % 2 == 1 ? dash + dash : dash }
            return stroke
        }
    }

    private static func rgba(_ c: FigmaPayload.Color?, opacity: Double = 1) -> RGBA {
        guard let c else { return .black }
        return RGBA(c.r, c.g, c.b, (c.a ?? 1) * opacity)
    }

    /// A Figma paint on a layer of `size`, which an oval's reach across is
    /// measured in.
    private mutating func paint(_ paint: FigmaPayload.Paint, size: Size2) -> Paint? {
        let opacity = paint.opacity ?? 1
        switch paint.type {
        case "SOLID":
            return .solid(Self.rgba(paint.color, opacity: opacity))
        case "GRADIENT_LINEAR", "GRADIENT_RADIAL", "GRADIENT_ANGULAR":
            let stops = (paint.stops ?? []).map { GradientStop(position: $0.position, color: Self.rgba($0.color, opacity: opacity)) }
            guard !stops.isEmpty else { return nil }
            // Figma's transform takes the box into the gradient's space; its
            // ends are fixed there, so they come back through the inverse.
            let t = Self.affine(paint.transform ?? [1, 0, 0, 1, 0, 0]).inverted ?? .identity
            if paint.type == "GRADIENT_LINEAR" {
                return .linearGradient(Gradient(stops: stops, start: t.apply(Vec2(0, 0.5)), end: t.apply(Vec2(1, 0.5))))
            }
            let center = t.apply(Vec2(0.5, 0.5)), edge = t.apply(Vec2(1, 0.5))
            if paint.type == "GRADIENT_ANGULAR" {
                // Clockwise from the edge point, as Twine's are, unless the
                // transform mirrors it: then it goes the other way round,
                // which is the stops turned end for end. An uneven stretch
                // (Figma's oval) is kept only as the angle of its start.
                let mirrored = t.a * t.d - t.b * t.c < 0
                let turned = mirrored ? stops.map { GradientStop(position: 1 - $0.position, color: $0.color) } : stops
                return .angularGradient(Gradient(stops: turned, start: center, end: edge))
            }
            // Figma's circle reaches to both (1, 0.5) and (0.5, 1): an oval
            // once its transform stretches one more than the other.
            return .radialGradient(Gradient.radial(stops: stops, center: center, edge: edge,
                                                   edgeAcross: t.apply(Vec2(0.5, 1)), in: size))
        case "IMAGE":
            guard let hash = paint.image, let id = image(hash) else { return nil }
            var p = ImagePaint(mediaID: id, opacity: opacity)
            switch paint.scaleMode {
            case "FIT": p.mode = .fit
            case "TILE":
                p.mode = .tile
                p.tileScale = paint.scalingFactor ?? 1
            case "CROP":
                p.mode = .crop
                // Figma's transform takes the box into the picture; the
                // picture's corners come back through the inverse.
                if let inverse = Self.affine(paint.imageTransform ?? [1, 0, 0, 1, 0, 0]).inverted {
                    let o = inverse.apply(.zero), x = inverse.apply(Vec2(1, 0)), y = inverse.apply(Vec2(0, 1))
                    p.crop = ImageCrop(x: o.x, y: o.y, width: x.x - o.x, height: y.y - o.y)
                }
            default: p.mode = .fill
            }
            // Only the turn within a full circle counts, so a huge angle
            // cannot overflow a whole number.
            let quarters = ((paint.rotation ?? 0) / 90).rounded().truncatingRemainder(dividingBy: 4)
            if p.mode != .crop, quarters.isFinite { p.quarterTurns = Int(quarters) }
            return .image(p)
        default:
            return nil
        }
    }

    /// A picture fill's bytes as an asset of the project, once each.
    private mutating func image(_ hash: String) -> UUID? {
        if let known = added[hash] { return known }
        guard let text = images[hash], let data = Data(base64Encoded: text), let asset = add(data, name: "Picture") else { return nil }
        added[hash] = asset.id
        return asset.id
    }

    private mutating func add(_ data: Data, name: String) -> MediaAsset? {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let known = media.first(where: { $0.asset.contentHash == hash }) { return known.asset }
        guard let size = SVGPictures.pixelSize(of: data), FileSafety.pictureFits(width: size.width, height: size.height) else { return nil }
        let ext = data.starts(with: [0xFF, 0xD8]) ? "jpg" : data.starts(with: [0x47, 0x49, 0x46]) ? "gif" : "png"
        let id = UUID()
        let asset = MediaAsset(id: id, kind: .image, fileName: "\(id.uuidString).\(ext)", originalName: "\(name).\(ext)",
                               contentHash: hash, pixelWidth: Int(size.width), pixelHeight: Int(size.height))
        media.append(SVGImport.EmbeddedMedia(asset: asset, data: data))
        return asset
    }

    // MARK: Effects and blending

    private static func effect(_ e: FigmaPayload.Effect) -> Effect? {
        let color = rgba(e.color)
        let shadow = DropShadow(color: RGBA(color.r, color.g, color.b), offset: Vec2(e.offset?.x ?? 0, e.offset?.y ?? 0),
                                blur: e.radius ?? 0, opacity: color.a, spread: e.spread ?? 0)
        let kind: EffectKind
        switch e.type {
        case "DROP_SHADOW": kind = .dropShadow(shadow)
        case "INNER_SHADOW": kind = .innerShadow(shadow)
        case "LAYER_BLUR": kind = .layerBlur(LayerBlur(radius: e.radius ?? 0))
        case "BACKGROUND_BLUR": kind = .backgroundBlur(BackgroundBlur(radius: e.radius ?? 0))
        case "GLASS":
            // Figma's numbers are its panel's (its dial's angle included),
            // fractions where the panel shows a percentage.
            let standard = Glass()
            kind = .glass(Glass(lightAngle: e.lightAngle ?? standard.lightAngle, lightIntensity: e.lightIntensity ?? standard.lightIntensity,
                                refraction: e.refraction ?? standard.refraction, depth: e.depth ?? standard.depth,
                                dispersion: e.dispersion ?? standard.dispersion, frost: e.radius ?? standard.frost,
                                splay: e.splay ?? standard.splay).held)
        default: return nil
        }
        return Effect(isEnabled: e.visible ?? true, kind: kind)
    }

    private static func blend(_ name: String?) -> BlendMode {
        switch name {
        case "DARKEN": return .darken
        case "MULTIPLY": return .multiply
        case "LINEAR_BURN": return .linearBurn
        case "COLOR_BURN": return .colorBurn
        case "LIGHTEN": return .lighten
        case "SCREEN": return .screen
        case "LINEAR_DODGE": return .linearDodge
        case "COLOR_DODGE": return .colorDodge
        case "OVERLAY": return .overlay
        case "SOFT_LIGHT": return .softLight
        case "HARD_LIGHT": return .hardLight
        case "DIFFERENCE": return .difference
        case "EXCLUSION": return .exclusion
        case "HUE": return .hue
        case "SATURATION": return .saturation
        case "COLOR": return .color
        case "LUMINOSITY": return .luminosity
        default: return .normal
        }
    }

    // MARK: Text

    /// Single-style text as Twine text. A font this Mac lacks is noted and
    /// shown in a stand-in, as Twine does for any missing font.
    private mutating func text(_ node: FigmaPayload.Node, size: Size2) -> Layer? {
        guard let t = node.text else { return nil }
        if NSFontManager.shared.availableMembers(ofFontFamily: t.family) == nil { missingFonts.insert(t.family) }
        let color: RGBA
        if let first = node.fills?.first(where: { $0.visible ?? true }), first.type == "SOLID" {
            color = Self.rgba(first.color, opacity: first.opacity ?? 1)
        } else {
            color = .black
        }
        let alignment: TextAlignment = t.align == "CENTER" ? .center : t.align == "RIGHT" ? .right : t.align == "JUSTIFIED" ? .justified : .left
        let content = TextContent(text: t.characters, fontFamily: t.family, fontWeight: Self.weight(t.style), fontSize: t.size,
                                  color: color, alignment: alignment, letterSpacing: t.letterSpacing ?? 0,
                                  lineHeight: t.lineHeight, sizing: t.autoResize == "WIDTH_AND_HEIGHT" ? .autoWidth : .fixedWidth)
        return Layer(name: node.name, content: .text(content), size: size, position: .zero)
    }

    /// A font style's name as a CSS weight: `Semi Bold` is 600.
    static func weight(_ style: String) -> Int {
        let s = style.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        let table: [(String, Int)] = [("extralight", 200), ("ultralight", 200), ("thin", 100), ("hairline", 100),
                                      ("semibold", 600), ("demibold", 600), ("extrabold", 800), ("ultrabold", 800),
                                      ("heavy", 800), ("black", 900), ("bold", 700), ("medium", 500), ("light", 300)]
        return table.first { s.contains($0.0) }?.1 ?? 400
    }

    // MARK: What Figma flattened

    /// A layer Figma drew as a picture, at its drawn box in the page.
    private mutating func picture(_ node: FigmaPayload.Node, into intoParent: Affine) -> Layer? {
        guard let png = node.png, let data = Data(base64Encoded: png), let b = node.bounds, b.count == 4, b[2] > 0, b[3] > 0,
              let asset = add(data, name: node.name) else { return nil }
        var layer = Layer(name: node.name, content: .shape(LayerFactory.picture(asset.id).cropped), size: Size2(b[2], b[3]),
                          position: .zero)
        place(&layer, local: Affine.translation(Vec2(b[0], b[1])).then(intoParent), box: Box(origin: .zero, size: layer.size))
        layer.isVisible = node.visible ?? true
        layer.isLocked = node.locked ?? false
        return layer
    }

    /// A layer Figma wrote as SVG, read by Twine's SVG reader into a group
    /// at the SVG's box in the page.
    private mutating func svgLayer(_ node: FigmaPayload.Node, into intoParent: Affine) -> Layer? {
        guard let svg = node.svg, let b = node.bounds, b.count == 4 else { return nil }
        let read: SVGImport.Result
        do {
            read = try SVGImport.read(Data(svg.utf8), name: node.name, center: Size2(b[2], b[3]).center, budget: budget)
        } catch SVGImport.ReadError.tooComplex {
            tooComplex = true
            return nil
        } catch {
            return nil
        }
        for item in read.media where !media.contains(where: { $0.asset.contentHash == item.asset.contentHash }) { media.append(item) }
        var layer = LayerFactory.group(in: Box(origin: .zero, size: read.layer.size), children: read.layer.children, name: node.name)
        place(&layer, local: Affine.translation(Vec2(b[0], b[1])).then(intoParent), box: Box(origin: .zero, size: layer.size))
        layer.isVisible = node.visible ?? true
        layer.isLocked = node.locked ?? false
        layer.opacity = min(max(node.opacity ?? 1, 0), 1)
        layer.blendMode = Self.blend(node.blend)
        return layer
    }
}

private extension ShapeContent {
    /// A picture filling its box exactly, as a drawing of a layer does.
    var cropped: ShapeContent {
        var s = self
        if case .image(var p) = s.fills.first?.paint {
            p.mode = .crop
            s.fills[0].paint = .image(p)
        }
        return s
    }
}
