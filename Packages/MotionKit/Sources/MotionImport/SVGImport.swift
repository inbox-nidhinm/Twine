import Foundation
import CryptoKit
import MotionModel
import MotionEvaluation
import MotionEditing

/// An SVG file read into Twine layers.
///
/// Paths, rectangles, circles, ellipses, lines, polylines and polygons
/// become shapes, rectangles and ellipses keeping their own kind wherever
/// their transform allows, with their fills (colours, gradients, pictures),
/// strokes, opacity, blend modes and fill rules. Groups stay groups, clip
/// paths and alpha masks become masks, embedded pictures become picture
/// fills, and the shadows and blurs Figma writes as filters become effects.
/// What cannot be made editable, text above all, is drawn by the system's
/// own SVG renderer into a sharp picture of just that part, in its place.
///
/// Everything is worked out in the SVG's own space, scaled to its final
/// size, so each layer's box is where it shows; the whole file comes in as a
/// frame, which clips as the SVG's viewport does.
public enum SVGImport {
    public struct Result: Sendable {
        /// The frame holding everything.
        public var layer: Layer
        /// Pictures the file carried or that were drawn from it, to add to
        /// the project with the layers.
        public var media: [EmbeddedMedia]
        /// How many parts had to become pictures.
        public var pictureCount: Int
    }

    public struct EmbeddedMedia: Sendable, Equatable {
        public var asset: MediaAsset
        public var data: Data
    }

    public enum ReadError: Error, Equatable {
        case notSVG
        /// The file declares entities that read other files or grow into
        /// others, which could pull a file from the Mac into the drawing or
        /// swell a few bytes into gigabytes.
        case entities
        /// Nested, or repeated through `use`, past what any drawing needs.
        case tooComplex
    }

    /// The largest SVG file read, in bytes: far past any drawing (Figma's
    /// largest exports are a few tens of megabytes), and read whole.
    public static let largestFile = 256_000_000

    /// How deep elements may nest, counting each `use` as a level.
    static let maxDepth = 256
    /// How many elements may be read, counting each one a `use` repeats.
    static let maxElements = 100_000
    /// How many elements all the pictures drawn from one file may take
    /// together, counted as `maxElements` is.
    static let maxPictureWork = 1_000_000
    /// How many pixels all the pictures drawn from one file may cover
    /// together. Each is drawn the size of the whole drawing, so a small
    /// file of many texts, or many pasted from Figma, could take hours;
    /// this is some five hundred pictures of a full HD drawing at twice its
    /// size, or sixty of the largest, about ten seconds in a release build.
    static let maxPicturePixels = 4_000_000_000.0

    /// What the system's drawing may still be handed, shared by every SVG in
    /// one Figma paste so the paste as a whole is held to it.
    public final class Budget: @unchecked Sendable {
        var work = SVGImport.maxPictureWork
        var pixels = SVGImport.maxPicturePixels
        public init() {}
    }

    /// Reads `data` as an SVG. The frame is named `name`, centred on
    /// `center`, and shrunk to fit `fitting` if it is larger. Pictures are
    /// drawn at `pictureScale` times their size.
    public static func read(_ data: Data, name: String, center: Vec2 = .zero, fitting: Size2? = nil,
                            pictureScale: Double = 2, budget: Budget = Budget()) throws -> Result {
        guard let data = utf8(data) else { throw ReadError.notSVG }
        guard !declaresRiskyEntities(data) else { throw ReadError.entities }
        guard nesting(of: data, limit: maxDepth) <= maxDepth else { throw ReadError.tooComplex }
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveWhitespace, .nodeLoadExternalEntitiesNever]),
              let root = document.rootElement(), root.localName == "svg" else { throw ReadError.notSVG }
        var reader = Reader(document: document, root: root, pictureScale: pictureScale, budget: budget)
        let result = reader.read(name: name, center: center, fitting: fitting)
        guard !reader.tooComplex else { throw ReadError.tooComplex }
        return result
    }

    /// The file in UTF-8, or nil when it is in an encoding read otherwise.
    /// The checks below look for markup by its bytes, which only works when
    /// `<!ENTITY` is written as those bytes: a file in UTF-16 slipped past
    /// them, and its entities grew a few bytes into gigabytes (4 October
    /// 2026). UTF-16 and UTF-32 are turned into UTF-8, with the declaration
    /// saying so; any other encoding must be one that writes plain letters
    /// as themselves (UTF-8, ASCII, the Latin and Windows single-byte ones).
    static func utf8(_ data: Data) -> Data? {
        let head = [UInt8](data.prefix(4))
        let wide: [([UInt8], String.Encoding, Int)] = [
            ([0x00, 0x00, 0xFE, 0xFF], .utf32BigEndian, 4), ([0xFF, 0xFE, 0x00, 0x00], .utf32LittleEndian, 4),
            ([0xFE, 0xFF], .utf16BigEndian, 2), ([0xFF, 0xFE], .utf16LittleEndian, 2),
            ([0x00, 0x00, 0x00, 0x3C], .utf32BigEndian, 0), ([0x3C, 0x00, 0x00, 0x00], .utf32LittleEndian, 0),
            ([0x00, 0x3C], .utf16BigEndian, 0), ([0x3C, 0x00], .utf16LittleEndian, 0),
        ]
        if let (_, encoding, mark) = wide.first(where: { head.starts(with: $0.0) }) {
            guard let text = String(data: Data(data.dropFirst(mark)), encoding: encoding) else { return nil }
            let declared = text.replacingOccurrences(of: #"^(<\?xml[^>]*?encoding\s*=\s*)(["'])[^"']*\2"#,
                                                     with: "$1$2UTF-8$2", options: .regularExpression)
            return Data(declared.utf8)
        }
        // No letter in these encodings has a zero byte; in every other one
        // (EBCDIC aside, which declares itself) most do.
        guard !data.contains(0) else { return nil }
        let start = String(decoding: data.prefix(200), as: UTF8.self)
        guard start.hasPrefix("<?xml") || start.hasPrefix("\u{FEFF}<?xml") else { return data }
        let declaration = start[..<(start.range(of: "?>")?.upperBound ?? start.endIndex)]
        guard let found = declaration.range(of: #"encoding\s*=\s*["']([^"']+)["']"#, options: .regularExpression) else { return data }
        let name = declaration[found].split(whereSeparator: { $0 == "\"" || $0 == "'" }).dropFirst().first.map { $0.lowercased() } ?? ""
        let plain = ["utf-8", "utf8", "us-ascii", "ascii", "latin1", "iso-latin-1"].contains(name)
            || name.hasPrefix("iso-8859-") || name.hasPrefix("windows-125")
        return plain ? data : nil
    }

    /// Whether the file declares an entity that is a file or a web address
    /// (`SYSTEM`, `PUBLIC`), a parameter entity, or one made of others.
    /// Plain text entities, which Illustrator writes, are fine.
    static func declaresRiskyEntities(_ data: Data) -> Bool {
        let opening = Data("<!ENTITY".utf8), close = UInt8(ascii: ">")
        var from = data.startIndex
        while let found = data.range(of: opening, in: from..<data.endIndex) {
            let end = data[found.upperBound...].firstIndex(of: close) ?? data.endIndex
            let body = String(decoding: data[found.upperBound..<end], as: UTF8.self)
            if body.contains("%") || body.contains("&") || body.contains("SYSTEM") || body.contains("PUBLIC") { return true }
            from = end
        }
        return false
    }

    /// How deep the file's elements nest, counted from its bytes before any
    /// XML reader sees them: the system's reader recurses, and a file nested
    /// a hundred thousand deep overflows its stack and crashes. Counting
    /// stops once past `limit`.
    static func nesting(of data: Data, limit: Int) -> Int {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            let lt = UInt8(ascii: "<"), gt = UInt8(ascii: ">"), slash = UInt8(ascii: "/")
            /// Where `end` next finishes from `start`, or the end of the file.
            func after(_ end: String, from start: Int) -> Int {
                let e = Array(end.utf8)
                var j = start
                while j + e.count <= n {
                    if b[j] == e[0], (1..<e.count).allSatisfy({ b[j + $0] == e[$0] }) { return j + e.count }
                    j += 1
                }
                return n
            }
            func starts(_ text: String, at i: Int) -> Bool {
                let t = Array(text.utf8)
                return i + t.count <= n && (0..<t.count).allSatisfy { b[i + $0] == t[$0] }
            }
            var i = 0, depth = 0, deepest = 0
            while i < n {
                guard b[i] == lt, i + 1 < n else { i += 1; continue }
                if b[i + 1] == slash {
                    depth -= 1
                    i = after(">", from: i + 2)
                } else if b[i + 1] == UInt8(ascii: "?") {
                    i = after("?>", from: i + 2)
                } else if starts("<!--", at: i) {
                    i = after("-->", from: i + 4)
                } else if starts("<![CDATA[", at: i) {
                    i = after("]]>", from: i + 9)
                } else if b[i + 1] == UInt8(ascii: "!") {
                    i = after(">", from: i + 2)
                } else {
                    // An opening tag, to its end past any quoted values.
                    var j = i + 1, quote: UInt8 = 0
                    while j < n {
                        let c = b[j]
                        if quote != 0 { if c == quote { quote = 0 } }
                        else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") { quote = c }
                        else if c == gt { break }
                        j += 1
                    }
                    if j < n, b[j - 1] != slash {
                        depth += 1
                        deepest = max(deepest, depth)
                        if deepest > limit { return deepest }
                    }
                    i = j + 1
                }
            }
            return deepest
        }
    }
}

extension SVGImport.Result {
    /// The result with every picture the project already has (the same
    /// bytes) taken from the project instead, so it is stored once.
    public func reusing(_ known: [MediaAsset]) -> SVGImport.Result {
        var swap: [UUID: UUID] = [:]
        var kept: [SVGImport.EmbeddedMedia] = []
        for item in media {
            if let existing = known.first(where: { $0.contentHash == item.asset.contentHash }) {
                swap[item.asset.id] = existing.id
            } else {
                kept.append(item)
            }
        }
        guard !swap.isEmpty else { return self }
        func remap(_ layer: Layer) -> Layer {
            var l = layer
            if var look = l.look {
                for i in look.fills.indices {
                    if case .image(var p) = look.fills[i].paint, let to = swap[p.mediaID] {
                        p.mediaID = to
                        look.fills[i].paint = .image(p)
                    }
                }
                l.look = look
            }
            l.children = l.children.map(remap)
            return l
        }
        return SVGImport.Result(layer: remap(layer), media: kept, pictureCount: pictureCount)
    }
}

// MARK: - The reader

private struct Reader {
    let document: XMLDocument
    let root: XMLElement
    let pictureScale: Double
    let sheet: SVGStyleSheet
    private var ids: [String: XMLElement] = [:]
    private var media: [SVGImport.EmbeddedMedia] = []
    private var pictureCount = 0
    private var counters: [String: Int] = [:]
    /// The SVG's viewport in its final size, for drawing parts as pictures.
    private var viewport = Size2(0, 0)
    private var rootTransform = Affine.identity
    /// A background blur Figma wrote as a `foreignObject` before the shape
    /// it belongs to.
    private var pendingBackgroundBlur: Double?
    /// The elements a `use` is drawing now, so one that reaches itself
    /// stops rather than going round for ever.
    private var expanding: Set<ObjectIdentifier> = []
    private var depth = 0
    private var visited = 0
    /// Set once the file nests or repeats past the limits; reading stops.
    private(set) var tooComplex = false
    /// What the system's drawing may still be handed for pictures.
    let budget: SVGImport.Budget

    init(document: XMLDocument, root: XMLElement, pictureScale: Double, budget: SVGImport.Budget) {
        self.budget = budget
        self.document = document
        self.root = root
        self.pictureScale = pictureScale
        sheet = SVGStyleSheet(document)
        for node in (try? document.nodes(forXPath: "//*[@id]")) ?? [] {
            if let e = node as? XMLElement, let id = e.attribute(forName: "id")?.stringValue { ids[id] = e }
        }
    }

    mutating func read(name: String, center: Vec2, fitting: Size2?) -> SVGImport.Result {
        // The viewport and the view box inside it, as SVG sizes them.
        let box = SVGNumber.list(attr(root, "viewBox") ?? "")
        var width = attr(root, "width").flatMap(SVGNumber.parse)
        var height = attr(root, "height").flatMap(SVGNumber.parse)
        if attr(root, "width")?.hasSuffix("%") == true { width = nil }
        if attr(root, "height")?.hasSuffix("%") == true { height = nil }
        let viewBox = box.count == 4 && box[2] > 0 && box[3] > 0 ? Box(origin: Vec2(box[0], box[1]), size: Size2(box[2], box[3])) : nil
        let w = width ?? viewBox?.width ?? 300, h = height ?? viewBox?.height ?? 150
        var t = Affine.identity
        if let viewBox {
            // xMidYMid meet, the default.
            let s = min(w / viewBox.width, h / viewBox.height)
            t = Affine.translation(Vec2(-viewBox.minX, -viewBox.minY)).then(.scale(Vec2(s, s)))
                .then(.translation(Vec2((w - viewBox.width * s) / 2, (h - viewBox.height * s) / 2)))
        }
        var fit = 1.0
        if let fitting, w > 0, h > 0 { fit = min(1, fitting.width / w, fitting.height / h) }
        rootTransform = t.then(.scale(Vec2(fit, fit)))
        viewport = Size2(w * fit, h * fit)

        let style = SVGStyle.of(root, parent: SVGStyle(values: ["fill": "black"]), sheet: sheet)
        let children = walkChildren(of: root, ctm: rootTransform, style: style)
        var frame = LayerFactory.frame(in: Box(origin: Vec2(center.x - viewport.width / 2, center.y - viewport.height / 2), size: viewport),
                                       name: name)
        frame.look = ShapeContent(geometry: .rectangle(cornerRadii: .zero))
        frame.children = Finite.layers(children)
        return SVGImport.Result(layer: frame, media: media, pictureCount: pictureCount)
    }

    // MARK: Walking

    private mutating func walkChildren(of element: XMLElement, ctm: Affine, style: SVGStyle) -> [Layer] {
        var out: [Layer] = []
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            out += walk(child, ctm: ctm, parentStyle: style)
        }
        return out
    }

    /// The layers for one element, back to front: a mask it needs first,
    /// then the element's own.
    private mutating func walk(_ element: XMLElement, ctm parent: Affine, parentStyle: SVGStyle) -> [Layer] {
        visited += 1
        guard !tooComplex, visited <= SVGImport.maxElements, depth < SVGImport.maxDepth else {
            tooComplex = true
            return []
        }
        depth += 1
        defer { depth -= 1 }
        let name = element.localName ?? ""
        let style = SVGStyle.of(element, parent: parentStyle, sheet: sheet)
        if style["display"] == "none" { return [] }
        let ctm = SVGTransform.parse(attr(element, "transform")).then(parent)

        var layers: [Layer]
        switch name {
        case "g", "a":
            layers = group(walkChildren(of: element, ctm: ctm, style: style), named: element, fallback: "Group")
        case "switch":
            let first = element.children?.compactMap({ $0 as? XMLElement }).first
            layers = first.map { walk($0, ctm: ctm, parentStyle: style) } ?? []
        case "svg":
            let x = number(element, "x"), y = number(element, "y")
            layers = group(walkChildren(of: element, ctm: Affine.translation(Vec2(x, y)).then(ctm), style: style),
                           named: element, fallback: "Group")
        case "use":
            guard let target = reference(attr(element, "href") ?? attr(element, "xlink:href")),
                  !expanding.contains(ObjectIdentifier(target)), !Self.contains(target, element) else { return [] }
            expanding.insert(ObjectIdentifier(target))
            defer { expanding.remove(ObjectIdentifier(target)) }
            let moved = Affine.translation(Vec2(number(element, "x"), number(element, "y"))).then(ctm)
            if target.localName == "symbol" {
                layers = group(walkChildren(of: target, ctm: moved, style: SVGStyle.of(target, parent: style, sheet: sheet)),
                               named: element, fallback: "Group")
            } else {
                layers = walk(target, ctm: moved, parentStyle: style)
            }
        case "path", "rect", "circle", "ellipse", "line", "polyline", "polygon":
            if style["visibility"] == "hidden" { return [] }
            guard let shape = shapeLayer(element, style: style, ctm: ctm) else { return [] }
            layers = [shape]
        case "image":
            layers = (pictureElement(element, ctm: ctm) ?? picture(of: element, ctm: parent)).map { [$0] } ?? []
        case "foreignObject":
            // Figma writes a background blur as HTML in a foreign object
            // just before its shape; the shape takes it.
            if let text = element.xmlString.range(of: #"backdrop-filter:\s*blur\(([0-9.]+)px\)"#, options: .regularExpression) {
                let digits = element.xmlString[text].filter { $0.isNumber || $0 == "." }
                pendingBackgroundBlur = Double(digits).map { $0 * 2 }
            }
            return []
        case "text":
            // Text is drawn by the system, as a picture of just this part.
            layers = picture(of: element, ctm: parent).map { [$0] } ?? []
        default:
            // Definitions, styles and titles draw nothing; nor do other
            // tools' own notes, such as Inkscape's.
            return []
        }
        return applyGroupEffects(layers, element: element, style: style, ctm: ctm, parentCTM: parent)
    }

    /// Opacity, blending, filters, clipping and masking on an element, put
    /// onto its layer, or onto a group of its layers.
    private mutating func applyGroupEffects(_ layers: [Layer], element: XMLElement, style: SVGStyle,
                                            ctm: Affine, parentCTM: Affine) -> [Layer] {
        guard !layers.isEmpty else { return [] }
        let opacity = style.fraction("opacity")
        let blend = style["mix-blend-mode"].flatMap(Self.blendMode)
        let effects = filterEffects(style["filter"])
        let clip = style["clip-path"].flatMap { clipLayer($0, element: element, ctm: ctm) }
        var mask: Layer?
        if let m = style["mask"], m != "none" {
            guard let made = maskLayer(m, element: element, ctm: ctm) else {
                // A mask Twine cannot make: the whole element as a picture.
                return picture(of: element, ctm: parentCTM).map { [$0] } ?? []
            }
            mask = made
        }
        if clip != nil, mask != nil { return picture(of: element, ctm: parentCTM).map { [$0] } ?? [] }
        let needsOne = opacity < 1 || blend != nil || !effects.isEmpty || clip != nil || mask != nil
        guard needsOne else { return layers }
        var target: Layer
        if layers.count == 1, layers[0].mask == nil { target = layers[0] } else {
            target = group(layers, named: element, fallback: "Group", always: true)[0]
        }
        target.opacity *= opacity
        if let blend { target.blendMode = blend }
        target.effects += effects.map { Effect(kind: $0) }
        var out: [Layer] = []
        if let source = clip ?? mask {
            out.append(source)
            target.mask = MaskReference(layerID: source.id)
        }
        out.append(target)
        return out
    }

    private static func blendMode(_ css: String) -> BlendMode? {
        switch css.lowercased() {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "darken": return .darken
        case "lighten": return .lighten
        case "color-dodge": return .colorDodge
        case "color-burn": return .colorBurn
        case "hard-light": return .hardLight
        case "soft-light": return .softLight
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        case "plus-darker": return .linearBurn
        case "plus-lighter": return .linearDodge
        default: return nil
        }
    }

    // MARK: Groups

    /// Layers gathered into a group whose box is around them, each moved
    /// into its space. A group of one with nothing of its own is just that
    /// one, unless `always`.
    private mutating func group(_ layers: [Layer], named element: XMLElement, fallback: String, always: Bool = false) -> [Layer] {
        guard !layers.isEmpty else { return [] }
        if layers.count == 1, !always { return layers }
        let boxes = layers.compactMap(Arrangement.box(of:))
        guard let first = boxes.first else { return layers }
        let bounds = boxes.dropFirst().reduce(first) { $0.union($1) }
        let shift = Vec2(-bounds.minX, -bounds.minY)
        return [LayerFactory.group(in: bounds, children: layers.map { $0.translated(by: shift) },
                                   name: layerName(element, fallback: fallback))]
    }

    // MARK: Shapes

    /// The element's outline in its own space, and whether it has a kind of
    /// its own that a layer can keep (a rectangle or an ellipse).
    private enum Outline {
        case rectangle(Box, rx: Double, ry: Double)
        case ellipse(Box)
        case path(BezierPath)
    }

    private func outline(_ element: XMLElement) -> Outline? {
        switch element.localName {
        case "rect":
            let w = number(element, "width"), h = number(element, "height")
            guard w > 0, h > 0 else { return nil }
            var rx = attr(element, "rx").flatMap(SVGNumber.parse), ry = attr(element, "ry").flatMap(SVGNumber.parse)
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            return .rectangle(Box(origin: Vec2(number(element, "x"), number(element, "y")), size: Size2(w, h)),
                              rx: min(rx ?? 0, w / 2), ry: min(ry ?? 0, h / 2))
        case "circle":
            let r = number(element, "r")
            guard r > 0 else { return nil }
            return .ellipse(Box(origin: Vec2(number(element, "cx") - r, number(element, "cy") - r), size: Size2(r * 2, r * 2)))
        case "ellipse":
            let rx = number(element, "rx"), ry = number(element, "ry")
            guard rx > 0, ry > 0 else { return nil }
            return .ellipse(Box(origin: Vec2(number(element, "cx") - rx, number(element, "cy") - ry), size: Size2(rx * 2, ry * 2)))
        case "line":
            var b = PathBuilder()
            b.move(to: Vec2(number(element, "x1"), number(element, "y1")))
            b.line(to: Vec2(number(element, "x2"), number(element, "y2")))
            return .path(b.finished())
        case "polyline", "polygon":
            let v = SVGNumber.list(attr(element, "points") ?? "")
            guard v.count >= 4 else { return nil }
            var b = PathBuilder()
            b.move(to: Vec2(v[0], v[1]))
            for i in stride(from: 2, to: v.count - 1, by: 2) { b.line(to: Vec2(v[i], v[i + 1])) }
            if element.localName == "polygon" { b.close() }
            return .path(b.finished())
        case "path":
            let p = SVGPathData.parse(attr(element, "d") ?? "")
            return p.subpaths.isEmpty ? nil : .path(p)
        default:
            return nil
        }
    }

    private static func path(of outline: Outline) -> BezierPath {
        switch outline {
        case .path(let p): return p
        case .ellipse(let box):
            return ShapeGeometry.ellipse(arc: .full).bezierPath(size: Size2(box.width, box.height))
                .transformed(by: .translation(Vec2(box.minX, box.minY)))
        case .rectangle(let box, let rx, let ry):
            if rx == ry {
                return ShapeGeometry.rectangle(cornerRadii: CornerRadii(all: rx)).bezierPath(size: Size2(box.width, box.height))
                    .transformed(by: .translation(Vec2(box.minX, box.minY)))
            }
            // Oval corners, as arcs.
            var b = PathBuilder()
            let (x0, y0, x1, y1) = (box.minX, box.minY, box.maxX, box.maxY)
            b.move(to: Vec2(x0 + rx, y0))
            b.line(to: Vec2(x1 - rx, y0))
            b.arc(rx: rx, ry: ry, rotation: 0, large: false, sweep: true, to: Vec2(x1, y0 + ry))
            b.line(to: Vec2(x1, y1 - ry))
            b.arc(rx: rx, ry: ry, rotation: 0, large: false, sweep: true, to: Vec2(x1 - rx, y1))
            b.line(to: Vec2(x0 + rx, y1))
            b.arc(rx: rx, ry: ry, rotation: 0, large: false, sweep: true, to: Vec2(x0, y1 - ry))
            b.line(to: Vec2(x0, y0 + ry))
            b.arc(rx: rx, ry: ry, rotation: 0, large: false, sweep: true, to: Vec2(x0 + rx, y0))
            b.close()
            return b.finished()
        }
    }

    private mutating func shapeLayer(_ element: XMLElement, style: SVGStyle, ctm: Affine) -> Layer? {
        guard let outline = outline(element) else { return nil }
        let isLine = ["line", "polyline"].contains(element.localName ?? "")
        let userPath = Self.path(of: outline)
        guard let userBounds = userPath.bounds else { return nil }

        // A rectangle or ellipse whose transform only moves, turns and
        // scales stays a rectangle or ellipse; everything else is a path
        // drawn through its transform.
        var layer: Layer
        let geometry: ShapeGeometry
        let widthScale = sqrt(abs(ctm.determinant))
        switch (outline, SVGTransform.decompose(ctm)) {
        case (.rectangle(let box, let rx, let ry), let parts?) where abs(rx * parts.scale.x - ry * parts.scale.y) < 1e-6:
            geometry = .rectangle(cornerRadii: CornerRadii(all: rx * parts.scale.x))
            layer = placed(box: box, ctm: ctm, scale: parts.scale, rotation: parts.rotation, geometry: geometry)
        case (.ellipse(let box), let parts?):
            geometry = .ellipse(arc: .full)
            layer = placed(box: box, ctm: ctm, scale: parts.scale, rotation: parts.rotation, geometry: geometry)
        default:
            let drawn = userPath.transformed(by: ctm)
            guard let b = drawn.bounds else { return nil }
            let local = drawn.transformed(by: .translation(Vec2(-b.minX, -b.minY)))
            layer = Layer(name: "", content: .shape(ShapeContent(geometry: .path(local))), size: Size2(b.width, b.height),
                          position: b.center)
            layer.transform.anchor = Size2(b.width, b.height).center
        }
        layer.name = layerName(element, fallback: Self.kindName(outline, isLine: isLine))

        var shape = ShapeContent(geometry: layer.look?.geometry ?? .line)
        shape.fillRule = style["fill-rule"] == "evenodd" ? .evenOdd : .nonZero
        if !isLine, let paint = paint(style["fill"], opacity: style.fraction("fill-opacity"), style: style,
                                      userBounds: userBounds, ctm: ctm, layer: layer) {
            shape.fills = [Fill(paint: paint)]
        }
        if let paint = paint(style["stroke"], opacity: style.fraction("stroke-opacity"), style: style,
                             userBounds: userBounds, ctm: ctm, layer: layer), !paint.isImage {
            let width = style.number("stroke-width", default: 1) * widthScale
            if width > 0 {
                var stroke = Stroke(paint: paint, width: width)
                stroke.cap = LineCap(rawValue: style["stroke-linecap"] ?? "") ?? .butt
                stroke.join = style["stroke-linejoin"] == "round" ? .round : style["stroke-linejoin"] == "bevel" ? .bevel : .miter
                let dashes = SVGNumber.list(style["stroke-dasharray"] ?? "").map { $0 * widthScale }
                if !dashes.isEmpty, dashes.contains(where: { $0 > 0 }) {
                    stroke.dashPattern = dashes.count % 2 == 1 ? dashes + dashes : dashes
                    stroke.dashOffset = style.number("stroke-dashoffset", default: 0) * widthScale
                }
                shape.strokes = [stroke]
            }
        }
        guard !shape.fills.isEmpty || !shape.strokes.isEmpty else { return nil }
        layer.look = shape
        if let blur = pendingBackgroundBlur {
            layer.effects.append(Effect(kind: .backgroundBlur(BackgroundBlur(radius: blur))))
            pendingBackgroundBlur = nil
        }
        return layer
    }

    /// A rectangle or ellipse layer for `box`, in the element's own space,
    /// placed through `ctm`, which only moves, turns and scales.
    private func placed(box: Box, ctm: Affine, scale: Vec2, rotation: Double, geometry: ShapeGeometry) -> Layer {
        let size = Size2(box.width * scale.x, box.height * scale.y)
        var layer = Layer(name: "", content: .shape(ShapeContent(geometry: geometry)), size: size, position: ctm.apply(box.center))
        layer.transform.rotation = rotation
        return layer
    }

    private static func kindName(_ outline: Outline, isLine: Bool) -> String {
        switch outline {
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .path: return isLine ? "Line" : "Vector"
        }
    }

    // MARK: Paint

    /// A fill or stroke: none, a colour, `currentColor`, or a gradient or a
    /// picture pattern by reference, with a colour to fall back on.
    private mutating func paint(_ value: String?, opacity: Double, style: SVGStyle, userBounds: Box,
                                ctm: Affine, layer: Layer) -> Paint? {
        guard var value = value?.trimmed, value != "none", !value.isEmpty else { return nil }
        if value == "currentColor" { value = style["color"] ?? "black" }
        if value.hasPrefix("url(") {
            let close = value.firstIndex(of: ")") ?? value.endIndex
            let ref = String(value[value.index(value.startIndex, offsetBy: 4)..<close]).trimmingCharacters(in: CharacterSet(charactersIn: "'\" #"))
            if let element = ids[ref] {
                switch element.localName {
                case "linearGradient", "radialGradient":
                    if let g = gradient(element, opacity: opacity, userBounds: userBounds, ctm: ctm, layer: layer) { return g }
                case "pattern":
                    if let p = patternPicture(element, opacity: opacity) { return p }
                default:
                    break
                }
            }
            let fallback = value[close...].dropFirst().trimmed
            return fallback.isEmpty ? nil : paint(fallback, opacity: opacity, style: style, userBounds: userBounds, ctm: ctm, layer: layer)
        }
        guard var color = SVGColor.parse(value) else { return nil }
        color.a *= opacity
        return .solid(color)
    }

    /// A gradient's attributes, following `href` to the gradients it builds
    /// on, the nearest winning.
    private func gradientAttribute(_ element: XMLElement, _ name: String) -> String? {
        var current: XMLElement? = element
        var seen = 0
        while let e = current, seen < 16 {
            if let v = attr(e, name) { return v }
            current = reference(attr(e, "href") ?? attr(e, "xlink:href"))
            seen += 1
        }
        return nil
    }

    private func gradientStops(_ element: XMLElement, opacity: Double) -> [GradientStop] {
        var current: XMLElement? = element
        var seen = 0
        while let e = current, seen < 16 {
            let stops = e.children?.compactMap({ $0 as? XMLElement }).filter { $0.localName == "stop" } ?? []
            if !stops.isEmpty {
                var last = 0.0
                return stops.map { stop in
                    let style = SVGStyle.of(stop, parent: SVGStyle(), sheet: sheet)
                    var offset = style["offset"].map { $0.hasSuffix("%") ? (Double($0.dropLast()) ?? 0) / 100 : Double($0) ?? 0 } ?? 0
                    offset = max(min(max(offset, 0), 1), last)
                    last = offset
                    var color = SVGColor.parse(style["stop-color"] ?? "black") ?? .black
                    color.a *= style.fraction("stop-opacity") * opacity
                    return GradientStop(position: offset, color: color)
                }
            }
            current = reference(attr(e, "href") ?? attr(e, "xlink:href"))
            seen += 1
        }
        return []
    }

    /// A gradient as Twine keeps one: its ends as fractions of the layer's
    /// box. Its points go from its own units (the shape's box, or the
    /// user space), through its transform and the element's, into the
    /// layer's box.
    private func gradient(_ element: XMLElement, opacity: Double, userBounds: Box, ctm: Affine, layer: Layer) -> Paint? {
        let stops = gradientStops(element, opacity: opacity)
        guard !stops.isEmpty else { return nil }
        if stops.count == 1 { return .solid(stops[0].color) }
        let boxUnits = gradientAttribute(element, "gradientUnits") != "userSpaceOnUse"
        func coordinate(_ name: String, _ fallback: Double) -> Double {
            guard let text = gradientAttribute(element, name) else { return fallback }
            if text.hasSuffix("%") { return (Double(text.dropLast()) ?? 0) / 100 * (boxUnits ? 1 : 100) }
            return Double(text) ?? fallback
        }
        let own = SVGTransform.parse(gradientAttribute(element, "gradientTransform"))
        let toUser = boxUnits ? own.then(Affine.scale(Vec2(userBounds.width, userBounds.height)))
            .then(.translation(Vec2(userBounds.minX, userBounds.minY))) : own
        let t = layer.transform
        guard let intoLayer = Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew).inverted,
              layer.size.width > 0, layer.size.height > 0 else { return .solid(stops[0].color) }
        func unit(_ p: Vec2) -> Vec2 {
            let local = intoLayer.apply(ctm.apply(toUser.apply(p)))
            return Vec2(local.x / layer.size.width, local.y / layer.size.height)
        }
        if element.localName == "linearGradient" {
            let a = Vec2(coordinate("x1", 0), coordinate("y1", 0)), b = Vec2(coordinate("x2", boxUnits ? 1 : 100), coordinate("y2", 0))
            return .linearGradient(Gradient(stops: stops, start: unit(a), end: unit(b)))
        }
        let c = Vec2(coordinate("cx", boxUnits ? 0.5 : 50), coordinate("cy", boxUnits ? 0.5 : 50))
        let r = coordinate("r", boxUnits ? 0.5 : 50)
        return .radialGradient(Gradient(stops: stops, start: unit(c), end: unit(Vec2(c.x + r, c.y))))
    }

    /// A pattern that is one picture, as Figma writes a picture fill: the
    /// picture's place in the shape's box becomes the fill's crop.
    private mutating func patternPicture(_ pattern: XMLElement, opacity: Double) -> Paint? {
        guard attr(pattern, "patternContentUnits") == "objectBoundingBox",
              let first = pattern.children?.compactMap({ $0 as? XMLElement }).first else { return nil }
        var image = first, t = Affine.identity
        if first.localName == "use" {
            guard let target = reference(attr(first, "href") ?? attr(first, "xlink:href")), target.localName == "image" else { return nil }
            t = SVGTransform.parse(attr(first, "transform"))
            image = target
        }
        guard image.localName == "image", abs(t.b) < 1e-9, abs(t.c) < 1e-9, t.a > 0, t.d > 0,
              let asset = embeddedPicture(image) else { return nil }
        let w = number(image, "width", default: Double(asset.pixelWidth ?? 1)), h = number(image, "height", default: Double(asset.pixelHeight ?? 1))
        let origin = t.apply(Vec2(number(image, "x"), number(image, "y")))
        let crop = ImageCrop(x: origin.x, y: origin.y, width: w * t.a, height: h * t.d)
        return .image(ImagePaint(mediaID: asset.id, mode: .crop, crop: crop, opacity: opacity))
    }

    /// An `<image>`: a rectangle filled with its picture.
    /// Nil when the picture is not carried in the file or is skewed, so it
    /// is drawn by the system instead.
    private mutating func pictureElement(_ element: XMLElement, ctm: Affine) -> Layer? {
        guard let asset = embeddedPicture(element) else { return nil }
        let w = number(element, "width", default: Double(asset.pixelWidth ?? 0))
        let h = number(element, "height", default: Double(asset.pixelHeight ?? 0))
        guard w > 0, h > 0, let parts = SVGTransform.decompose(ctm) else { return nil }
        let box = Box(origin: Vec2(number(element, "x"), number(element, "y")), size: Size2(w, h))
        var layer = placed(box: box, ctm: ctm, scale: parts.scale, rotation: parts.rotation, geometry: .rectangle(cornerRadii: .zero))
        let aspect = attr(element, "preserveAspectRatio") ?? ""
        let mode: ImageScaleMode = aspect.hasPrefix("none") ? .crop : aspect.contains("slice") ? .fill : .fit
        layer.look = ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                  fills: [Fill(paint: .image(ImagePaint(mediaID: asset.id, mode: mode)))])
        layer.name = layerName(element, fallback: "Picture")
        return layer
    }

    /// The picture an `<image>` carries in a `data:` address, added once.
    private mutating func embeddedPicture(_ image: XMLElement) -> MediaAsset? {
        guard let href = attr(image, "href") ?? attr(image, "xlink:href"), href.hasPrefix("data:image/"),
              let comma = href.firstIndex(of: ",") else { return nil }
        let header = href[..<comma]
        guard header.hasSuffix(";base64"), let data = Data(base64Encoded: String(href[href.index(after: comma)...]),
                                                            options: .ignoreUnknownCharacters) else { return nil }
        let ext = header.contains("png") ? "png" : header.contains("jpeg") || header.contains("jpg") ? "jpg"
            : header.contains("webp") ? "webp" : header.contains("gif") ? "gif" : "png"
        return add(data, ext: ext, originalName: layerName(image, fallback: "Picture"))
    }

    /// A picture's bytes as an asset of the project, the same bytes kept once.
    private mutating func add(_ data: Data, ext: String, originalName: String) -> MediaAsset? {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        if let known = media.first(where: { $0.asset.contentHash == hash }) { return known.asset }
        guard let size = SVGPictures.pixelSize(of: data), FileSafety.pictureFits(width: size.width, height: size.height) else { return nil }
        let id = UUID()
        let asset = MediaAsset(id: id, kind: .image, fileName: "\(id.uuidString).\(ext)", originalName: "\(originalName).\(ext)",
                               contentHash: hash, pixelWidth: Int(size.width), pixelHeight: Int(size.height))
        media.append(SVGImport.EmbeddedMedia(asset: asset, data: data))
        return asset
    }

    // MARK: Clipping, masking, filters

    /// Whether `element` is `outer` or inside it.
    private static func contains(_ outer: XMLElement, _ element: XMLElement) -> Bool {
        var node: XMLNode? = element
        while let n = node {
            if n === outer { return true }
            node = n.parent
        }
        return false
    }

    private func reference(_ text: String?) -> XMLElement? {
        guard var t = text?.trimmed, !t.isEmpty else { return nil }
        if t.hasPrefix("url(") { t = String(t.dropFirst(4).prefix { $0 != ")" }) }
        return ids[t.trimmingCharacters(in: CharacterSet(charactersIn: "'\" #"))]
    }

    /// The outline of everything in a clip path or a mask, drawn through
    /// their transforms into the composition, as one path.
    private func combinedOutline(of container: XMLElement, units boxUnits: Bool, element: XMLElement, ctm: Affine) -> BezierPath? {
        var t = SVGTransform.parse(attr(container, "transform")).then(ctm)
        if boxUnits {
            guard let b = userBounds(of: element) else { return nil }
            t = Affine.scale(Vec2(b.width, b.height)).then(.translation(Vec2(b.minX, b.minY))).then(t)
        }
        var subpaths: [Subpath] = []
        for child in container.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            var shape = child, childT = SVGTransform.parse(attr(child, "transform")).then(t)
            if child.localName == "use", let target = reference(attr(child, "href") ?? attr(child, "xlink:href")) {
                childT = SVGTransform.parse(attr(target, "transform"))
                    .then(Affine.translation(Vec2(number(child, "x"), number(child, "y")))).then(childT)
                shape = target
            }
            guard let o = outline(shape) else { return nil }
            subpaths += Self.path(of: o).transformed(by: childT).subpaths
        }
        return subpaths.isEmpty ? nil : BezierPath(subpaths: subpaths)
    }

    /// The box of an element's own outline, or of everything inside a group,
    /// in its user space, for clips measured in it.
    private func userBounds(of element: XMLElement) -> Box? {
        if let o = outline(element) { return Self.path(of: o).bounds }
        let inside = element.children?.compactMap { $0 as? XMLElement }.compactMap { child -> Box? in
            guard let b = userBounds(of: child) else { return nil }
            let t = SVGTransform.parse(attr(child, "transform"))
            return Box(around: b.corners.map(t.apply))
        } ?? []
        guard let first = inside.first else { return nil }
        return inside.dropFirst().reduce(first) { $0.union($1) }
    }

    /// A shape to clip by, filled solid, for a `clip-path`.
    private mutating func clipLayer(_ value: String, element: XMLElement, ctm: Affine) -> Layer? {
        guard value != "none", let clip = reference(value), clip.localName == "clipPath",
              let path = combinedOutline(of: clip, units: attr(clip, "clipPathUnits") == "objectBoundingBox",
                                         element: element, ctm: ctm) else { return nil }
        var layer = pathLayer(path, name: layerName(clip, fallback: "Clip"))
        if clip.children?.compactMap({ $0 as? XMLElement }).first.flatMap({ SVGStyle.of($0, parent: SVGStyle(), sheet: sheet)["clip-rule"] }) == "evenodd",
           var look = layer.look {
            look.fillRule = .evenOdd
            layer.look = look
        }
        return layer
    }

    /// A mask Twine can draw, as the layer whose alpha shows the element:
    /// an alpha mask, or a luminance mask of white shapes, which is the same.
    /// One shape keeps its own paint, so a gradient mask fades; several are
    /// joined, if every one is solid white. Nil for any other.
    private mutating func maskLayer(_ value: String, element: XMLElement, ctm: Affine) -> Layer? {
        guard let mask = reference(value), mask.localName == "mask" else { return nil }
        let maskStyle = SVGStyle.of(mask, parent: SVGStyle(), sheet: sheet)
        let alpha = maskStyle["mask-type"] == "alpha"
        let shapes = mask.children?.compactMap { $0 as? XMLElement } ?? []
        let boxUnits = attr(mask, "maskContentUnits") == "objectBoundingBox"
        func isWhite(_ e: XMLElement) -> Bool {
            let s = SVGStyle.of(e, parent: SVGStyle(values: ["fill": "black"]), sheet: sheet)
            guard let c = SVGColor.parse(s["fill"] ?? "black") else { return false }
            return c.r > 0.99 && c.g > 0.99 && c.b > 0.99 && s["stroke"] == nil
        }
        if shapes.count == 1, !boxUnits, alpha || isWhite(shapes[0]) {
            let style = SVGStyle.of(shapes[0], parent: SVGStyle(values: ["fill": "black"]), sheet: sheet)
            let t = SVGTransform.parse(attr(shapes[0], "transform")).then(ctm)
            guard var layer = shapeLayer(shapes[0], style: style, ctm: t) else { return nil }
            layer.name = layerName(mask, fallback: "Mask")
            return layer
        }
        guard shapes.allSatisfy({ alpha || isWhite($0) }),
              let path = combinedOutline(of: mask, units: boxUnits, element: element, ctm: ctm) else { return nil }
        return pathLayer(path, name: layerName(mask, fallback: "Mask"))
    }

    /// A black shape for a path in the composition, as clips and masks are.
    private func pathLayer(_ path: BezierPath, name: String) -> Layer {
        let b = path.bounds ?? Box(minX: 0, minY: 0, maxX: 0, maxY: 0)
        let local = path.transformed(by: .translation(Vec2(-b.minX, -b.minY)))
        var layer = Layer(name: name, content: .shape(ShapeContent(geometry: .path(local), fills: [Fill(paint: .color(.black))])),
                          size: Size2(b.width, b.height), position: b.center)
        layer.transform.anchor = Size2(b.width, b.height).center
        return layer
    }

    private func filterEffects(_ value: String?) -> [EffectKind] {
        guard let value, value != "none", let filter = reference(value), filter.localName == "filter" else { return [] }
        return SVGFilters.effects(filter)
    }

    // MARK: Pictures of what cannot be edited

    /// A picture of one element, drawn by the system from an SVG holding just
    /// it (and everything it may refer to), trimmed to what it draws and
    /// placed there. `ctm` is its parent's, so it sits where it did.
    private mutating func picture(of element: XMLElement, ctm: Affine) -> Layer? {
        guard viewport.width > 0, viewport.height > 0 else { return nil }
        budget.pixels -= SVGPictures.pixels(size: viewport, scale: pictureScale)
        guard budget.pixels >= 0 else { tooComplex = true; return nil }
        guard let svg = pictureSVG(element, ctm: ctm) else { return nil }
        let name = layerName(element, fallback: element.localName == "text" ? "Text" : "Picture")
        guard let drawn = SVGPictures.draw(svg, size: viewport, scale: pictureScale),
              let asset = add(drawn.png, ext: "png", originalName: name) else { return nil }
        pictureCount += 1
        var layer = Layer(name: name,
                          content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                                       fills: [Fill(paint: .image(ImagePaint(mediaID: asset.id, mode: .crop)))])),
                          size: Size2(drawn.box.width, drawn.box.height), position: drawn.box.center)
        layer.transform.anchor = Size2(drawn.box.width, drawn.box.height).center
        return layer
    }

    /// An SVG the size of the whole viewport holding the element, inside its
    /// ancestors' own styles (so it inherits what it did), with every style
    /// sheet of the original and the definitions it refers to. Nil, and the
    /// file too complex, when drawing it would take more than
    /// `maxElements`, or all the pictures together more than
    /// `maxPictureWork`, counting each element once for every `use` that
    /// repeats it: the reader never walks into definitions, and the system's
    /// drawing repeats them without limit, so a kilobyte of uses of uses
    /// once took it hours (4 October 2026). It used to be handed every
    /// definition for every picture.
    private mutating func pictureSVG(_ element: XMLElement, ctm: Affine) -> String? {
        var styles = ""
        for node in (try? document.nodes(forXPath: "//*[local-name()='style']")) ?? [] {
            styles += node.xmlString
        }
        var ancestors: [XMLElement] = []
        var current = element.parent as? XMLElement
        while let e = current, e !== root { ancestors.insert(e, at: 0); current = e.parent as? XMLElement }
        ancestors.insert(root, at: 0)
        var open = "", close = ""
        let skipped: Set<String> = ["id", "transform", "clip-path", "mask", "filter", "opacity", "x", "y", "width", "height",
                                    "viewBox", "xmlns", "xmlns:xlink", "version", "style"]
        for a in ancestors {
            var attrs = ""
            for attribute in a.attributes ?? [] {
                guard let name = attribute.name, !skipped.contains(name), var value = attribute.stringValue else { continue }
                if name == "font-weight" { value = ["normal": "400", "bold": "700", "bolder": "700", "lighter": "300"][value.lowercased()] ?? value }
                attrs += " \(name)=\"\(Self.escape(value))\""
            }
            if let style = attr(a, "style") {
                let kept = SVGStyle.declarations(style).filter { SVGStyle.inherited.contains($0.0) }
                if !kept.isEmpty { attrs += " style=\"\(Self.escape(kept.map { "\($0.0):\($0.1)" }.joined(separator: ";")))\"" }
            }
            open += "<g\(attrs)>"
            close = "</g>" + close
        }
        let body = Self.drawable(element)
        // What the picture refers to, and what that refers to, each once:
        // never the element itself or what holds it, which would loop.
        var included: [XMLElement] = []
        var pending = Self.references(in: body + open + styles)
        var seen: Set<String> = []
        while let id = pending.popLast() {
            guard seen.insert(id).inserted, let target = ids[id], !Self.contains(target, element), !Self.contains(element, target),
                  !included.contains(where: { Self.contains($0, target) }) else { continue }
            guard seen.count <= SVGImport.maxElements else { tooComplex = true; return nil }
            included.removeAll { Self.contains(target, $0) }
            included.append(target)
            pending += Self.references(in: target.xmlString)
        }
        var sizes: [ObjectIdentifier: Int] = [:]
        let work = ([element] + included).reduce(0) { $0 + expandedSize($1, sizes: &sizes, depth: 0) }
        budget.work -= work
        guard work <= SVGImport.maxElements, budget.work >= 0 else { tooComplex = true; return nil }
        let defs = "<defs>" + included.map(\.xmlString).joined() + "</defs>" + styles
        // A picture inside too large to take in is too large for the
        // system to draw either: it would decode it whole.
        guard !Self.carriesOversizedPicture(body + defs) else { return nil }
        let m = ctm
        return """
        <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="\(viewport.width)" height="\(viewport.height)" viewBox="0 0 \(viewport.width) \(viewport.height)">\
        \(defs)<g transform="matrix(\(m.a) \(m.b) \(m.c) \(m.d) \(m.tx) \(m.ty))">\(open)\(body)\(close)</g></svg>
        """
    }

    /// How many elements drawing `element` takes, each `use` counted as
    /// what it repeats, up to one past `maxElements`. A `use` reaching what
    /// holds it counts nothing, as nothing is drawn for it.
    private func expandedSize(_ element: XMLElement, sizes: inout [ObjectIdentifier: Int], depth: Int) -> Int {
        let key = ObjectIdentifier(element)
        if let known = sizes[key] { return known }
        let over = SVGImport.maxElements + 1
        guard depth < SVGImport.maxDepth else { return over }
        sizes[key] = 0
        var total = 1
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] where total <= over {
            total += expandedSize(child, sizes: &sizes, depth: depth + 1)
        }
        if element.localName == "use", total <= over,
           let target = reference(attr(element, "href") ?? attr(element, "xlink:href")) {
            total += expandedSize(target, sizes: &sizes, depth: depth + 1)
        }
        total = min(total, over)
        sizes[key] = total
        return total
    }

    /// Whether `text` holds a picture (as a `data:` address) past
    /// `FileSafety.pictureFits`, or one that cannot be read.
    private static func carriesOversizedPicture(_ text: String) -> Bool {
        guard text.contains("data:image/"),
              let expression = try? NSRegularExpression(pattern: #"data:image/[^;,"']*;base64,([A-Za-z0-9+/=\s]+)"#) else { return false }
        return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains { match in
            guard let range = Range(match.range(at: 1), in: text),
                  let data = Data(base64Encoded: String(text[range]), options: .ignoreUnknownCharacters),
                  let size = SVGPictures.pixelSize(of: data) else { return true }
            return !FileSafety.pictureFits(width: size.width, height: size.height)
        }
    }

    /// The ids `text` refers to, by `url(#...)` or `href="#..."`.
    private static func references(in text: String) -> [String] {
        let pattern = #"(?:url\((?:\s|['"]|&quot;|&apos;)*#|href\s*=\s*["']#)([^'"\)\s&]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: whole).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// The element as the system draws it right. It places a `<tspan>` with
    /// its own `x` and `y` wrongly (squashed to the top), and Figma writes
    /// every line of text as one, so each becomes a `<text>` of its own with
    /// the text's styles and its own.
    ///
    /// It also only reads a font's weight as a number, so `bold` and the
    /// like become one.
    private static func drawable(_ element: XMLElement) -> String {
        guard let copy = element.copy() as? XMLElement else { return element.xmlString }
        numberWeights(copy)
        return spansAsTexts(copy)
    }

    /// `font-weight` written as a word, in attributes and styles, written as
    /// a number throughout `element`.
    private static func numberWeights(_ element: XMLElement) {
        let words = ["normal": "400", "bold": "700", "bolder": "700", "lighter": "300"]
        if let w = element.attribute(forName: "font-weight")?.stringValue, let n = words[w.trimmed.lowercased()] {
            element.attribute(forName: "font-weight")?.stringValue = n
        }
        if let style = element.attribute(forName: "style")?.stringValue {
            let fixed = SVGStyle.declarations(style).map { key, value in
                "\(key):\(key == "font-weight" ? words[value.lowercased()] ?? value : value)"
            }
            element.attribute(forName: "style")?.stringValue = fixed.joined(separator: ";")
        }
        for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] { numberWeights(child) }
    }

    private static func spansAsTexts(_ element: XMLElement) -> String {
        guard element.localName == "text",
              let spans = element.children?.compactMap({ $0 as? XMLElement }).filter({ $0.localName == "tspan" }),
              !spans.isEmpty else { return element.xmlString }
        let own = (element.attributes ?? []).filter { $0.name != "x" && $0.name != "y" && $0.name != "dx" && $0.name != "dy" }
        var out = ""
        for span in spans {
            let text = XMLElement(name: "text")
            var names = Set<String>()
            for attribute in (span.attributes ?? []) + own {
                guard let name = attribute.name, !names.contains(name), let copy = attribute.copy() as? XMLNode else { continue }
                names.insert(name)
                text.addAttribute(copy)
            }
            if !names.contains("x"), let x = element.attribute(forName: "x")?.copy() as? XMLNode { text.addAttribute(x) }
            if !names.contains("y"), let y = element.attribute(forName: "y")?.copy() as? XMLNode { text.addAttribute(y) }
            text.stringValue = span.stringValue ?? ""
            out += text.xmlString
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;").replacingOccurrences(of: "<", with: "&lt;")
    }

    // MARK: Small things

    private func attr(_ element: XMLElement, _ name: String) -> String? {
        if let v = element.attribute(forName: name)?.stringValue { return v }
        // `xlink:href` read by its local name too.
        if name.hasPrefix("xlink:") {
            return element.attributes?.first { $0.localName == String(name.dropFirst(6)) && $0.name != "href" }?.stringValue
        }
        return nil
    }

    private func number(_ element: XMLElement, _ name: String, default fallback: Double = 0) -> Double {
        attr(element, name).flatMap(SVGNumber.parse) ?? fallback
    }

    /// The element's `id`, read as Figma writes names (underscores for
    /// spaces), or its kind numbered.
    private mutating func layerName(_ element: XMLElement, fallback: String) -> String {
        if let id = attr(element, "id"), !id.isEmpty, !id.hasPrefix("clip"), !id.hasPrefix("mask"), !id.hasPrefix("paint"),
           !id.hasPrefix("filter"), !id.hasPrefix("pattern"), !id.hasPrefix("image") {
            return id.replacingOccurrences(of: "_", with: " ")
        }
        let n = (counters[fallback] ?? 0) + 1
        counters[fallback] = n
        return "\(fallback) \(n)"
    }
}
