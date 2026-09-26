import Foundation
import QuartzCore
import CoreImage
import MotionModel
import MotionEvaluation

/// Draws scenes as a Core Animation layer tree, composited on the GPU.
///
/// Core Animation's own animation is switched off: every property is set
/// directly from the scene inside a transaction with actions disabled, so a
/// scrub lands exactly on the frame asked for and nothing eases in between.
///
/// Layers are kept between frames and matched to the scene by layer id, so a
/// frame only changes what moved. Every layer gets a container `CALayer`
/// carrying its transform, opacity, shadow, blur and clipping; a group's
/// children are that container's sublayers, which is what makes group opacity
/// and group transforms apply to the children as one picture.
public final class CoreAnimationRenderer: SceneRenderer {
    /// The composition, `size` points across with its origin at the top-left.
    /// Put it in a layer whose coordinates run downward (a flipped view, or a
    /// layer with `isGeometryFlipped`) and scale it with a transform to zoom.
    public let rootLayer = CALayer()
    private let backgroundLayer = CALayer()
    private let contentLayer = CALayer()
    private var nodes: [UUID: Node] = [:]

    /// Whether pictures (text now; images and video later) are drawn upside
    /// down and must be turned over. Off screen the layer tree runs y up and
    /// the texture's rows turn it the right way, which shapes never notice
    /// but a picture does. The offscreen renderer turns this on.
    public var flipsContents = false {
        didSet { for node in nodes.values { node.flipsContents = flipsContents } }
    }

    /// Where image and video layers get their pictures. Without one they draw
    /// as a grey box, as they do when a file is missing.
    public var media: MediaProvider?

    /// How many device pixels to rasterise per point. Raise it for Retina
    /// screens and high-resolution exports.
    public var contentsScale: CGFloat = 2 {
        didSet { for node in nodes.values { node.setContentsScale(contentsScale) } }
    }

    public init() {
        for layer in [rootLayer, backgroundLayer, contentLayer] {
            layer.anchorPoint = .zero
            layer.actions = Node.noActions
        }
        rootLayer.masksToBounds = true
        rootLayer.addSublayer(backgroundLayer)
        rootLayer.addSublayer(contentLayer)
    }

    public func render(_ scene: ResolvedScene) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = CGRect(origin: .zero, size: scene.size.cg)
        if rootLayer.bounds != bounds {
            rootLayer.bounds = bounds
            backgroundLayer.frame = bounds
            contentLayer.frame = bounds
        }
        backgroundLayer.backgroundColor = scene.background?.cgColor

        var seen = Set<UUID>()
        var children: [UUID?: [CALayer]] = [:]
        for resolved in scene.layers {
            let node = nodes[resolved.id] ?? {
                let made = Node(scale: contentsScale)
                made.flipsContents = flipsContents
                nodes[resolved.id] = made
                return made
            }()
            node.update(resolved, media: media)
            seen.insert(resolved.id)
            children[resolved.parentID, default: []].append(node.container)
        }

        for (id, node) in nodes where !seen.contains(id) {
            node.container.removeFromSuperlayer()
            nodes[id] = nil
        }

        Self.setSublayers(contentLayer, children[nil] ?? [])
        for resolved in scene.layers where resolved.content == .group {
            if let node = nodes[resolved.id] { Self.setSublayers(node.container, children[resolved.id] ?? []) }
        }
    }

    /// Only touches the tree when the order actually changed.
    private static func setSublayers(_ parent: CALayer, _ layers: [CALayer]) {
        let current = parent.sublayers ?? []
        if current.count == layers.count && zip(current, layers).allSatisfy({ $0 === $1 }) { return }
        parent.sublayers = layers
    }
}

// MARK: - One layer

private final class Node {
    /// No implicit animation on anything this renderer creates. Never
    /// mutated after it is made, and `NSNull` is immutable, so sharing it
    /// between an export's thread and the main thread is safe.
    nonisolated(unsafe) static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "transform": NSNull(), "opacity": NSNull(),
        "sublayers": NSNull(), "contents": NSNull(), "path": NSNull(), "fillColor": NSNull(),
        "strokeColor": NSNull(), "lineWidth": NSNull(), "strokeStart": NSNull(), "strokeEnd": NSNull(),
        "shadowColor": NSNull(), "shadowOffset": NSNull(), "shadowRadius": NSNull(), "shadowOpacity": NSNull(),
        "filters": NSNull(), "colors": NSNull(), "locations": NSNull(), "startPoint": NSNull(),
        "endPoint": NSNull(), "frame": NSNull(), "mask": NSNull(), "backgroundColor": NSNull(),
        "lineDashPattern": NSNull(), "lineDashPhase": NSNull(), "masksToBounds": NSNull(), "hidden": NSNull(), "shadowPath": NSNull(),
    ]

    let container = CALayer()
    var flipsContents = false
    private var scale: CGFloat
    /// The kinds of fill and stroke layers currently built, so they are only
    /// rebuilt when a paint changes kind rather than on every frame.
    private var signature: [String] = []
    private var paintLayers: [PaintLayers] = []
    private var blurRadius = 0.0
    /// Frosted glass: the blurred background, under the fills and clipped
    /// to the shape. Made when a layer first needs one.
    private var backdrop: CALayer?
    private let backdropMask = CAShapeLayer()
    private var backdropRadius = 0.0
    /// A text layer's words: the current text, and the previous one while a
    /// Counter or Change Text moves from one to the other.
    private var textLayers: [CALayer] = []
    private var textKeys: [TextImage.Key?] = [nil, nil]
    private var textImages: [TextImage?] = [nil, nil]
    /// An image or video layer's picture.
    private var mediaLayer: CALayer?

    init(scale: CGFloat) {
        self.scale = scale
        container.anchorPoint = .zero
        container.position = .zero
        container.allowsGroupOpacity = true
        container.actions = Self.noActions
    }

    func setContentsScale(_ scale: CGFloat) {
        self.scale = scale
        container.contentsScale = scale
        for p in paintLayers { p.setContentsScale(scale) }
        // Text is a picture drawn at a scale, so it is drawn again.
        textKeys = [nil, nil]
    }

    func update(_ layer: ResolvedLayer, media: MediaProvider?) {
        container.bounds = CGRect(origin: .zero, size: layer.size.cg)
        // The anchor point stays at the layer's origin and the whole local
        // transform goes in the matrix, so a layer of zero width or height
        // (a line) still turns about its real anchor.
        container.transform = layer.transform.caTransform
        container.opacity = Float(layer.opacity)
        container.masksToBounds = layer.clipsContent

        // Blur amounts arrive as Figma measures them, twice the Gaussian's
        // standard deviation. Core Animation's shadow radius is the standard
        // deviation, as is the blur filter's radius.
        if let shadow = layer.shadow {
            container.shadowColor = shadow.color.cgColor
            container.shadowOffset = CGSize(width: shadow.offset.x, height: shadow.offset.y)
            container.shadowRadius = shadow.blur / 2
            container.shadowOpacity = Float(shadow.opacity)
            container.shadowPath = spreadPath(layer, by: shadow.spread)
        } else {
            container.shadowOpacity = 0
            container.shadowPath = nil
        }

        if layer.blur != blurRadius {
            blurRadius = layer.blur
            container.filters = layer.blur > 0 ? [Blur.filter(amount: layer.blur)] : nil
        }

        switch layer.content {
        case .shape(let shape):
            updateShape(shape, size: layer.size)
            updateBackdrop(layer.backgroundBlur, path: shape.path.cgPath, size: layer.size)
        case .group:
            // A group's sublayers are its children, set by the renderer.
            if !signature.isEmpty { clearPaint() }
        case .text(let text):
            if !signature.isEmpty { clearPaint() }
            updateText(text, size: layer.size)
        case .image(let id):
            if !signature.isEmpty { clearPaint() }
            updateMedia(media?.image(id), size: layer.size)
        case .video(let id, let time):
            if !signature.isEmpty { clearPaint() }
            updateMedia(media?.videoFrame(id, at: time), size: layer.size)
        }
        if case .text = layer.content {} else if !textLayers.isEmpty { clearText() }
        switch layer.content {
        case .image, .video: break
        default:
            mediaLayer?.removeFromSuperlayer()
            mediaLayer = nil
        }
    }

    /// The shadow's outline grown by `spread`, or shrunk for a negative one.
    /// Nil leaves Core Animation to shadow whatever the layer draws, which
    /// is what a spread of 0 and every non-shape layer want.
    private func spreadPath(_ layer: ResolvedLayer, by spread: Double) -> CGPath? {
        guard spread != 0, case .shape(let shape) = layer.content, shape.isClosed else { return nil }
        let path = shape.path.cgPath
        let band = path.copy(strokingWithWidth: abs(spread) * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return spread > 0 ? path.union(band) : path.subtracting(band)
    }

    private func updateBackdrop(_ blur: BackgroundBlur?, path: CGPath, size: Size2) {
        guard let blur else {
            backdrop?.removeFromSuperlayer()
            return
        }
        if backdrop == nil {
            guard let made = Blur.makeBackdrop() else { return }
            made.anchorPoint = .zero
            made.actions = Self.noActions
            backdropMask.anchorPoint = .zero
            backdropMask.actions = Self.noActions
            backdropMask.fillColor = CGColor(gray: 0, alpha: 1)
            made.mask = backdropMask
            backdrop = made
        }
        guard let backdrop else { return }
        if container.sublayers?.first !== backdrop { container.insertSublayer(backdrop, at: 0) }
        backdrop.frame = CGRect(origin: .zero, size: size.cg)
        backdropMask.frame = backdrop.bounds
        backdropMask.path = path
        backdrop.opacity = Float(blur.blend)
        if blur.radius != backdropRadius {
            backdropRadius = blur.radius
            backdrop.filters = [Blur.filter(amount: blur.radius)]
        }
    }

    /// The picture stretched to the layer's box, or a grey box where the file
    /// is missing, so the layer can still be seen and picked.
    private func updateMedia(_ image: CGImage?, size: Size2) {
        if mediaLayer == nil {
            let l = CALayer()
            l.actions = Self.noActions
            l.contentsGravity = .resize
            container.sublayers = [l]
            mediaLayer = l
        }
        guard let mediaLayer else { return }
        mediaLayer.transform = CATransform3DIdentity
        mediaLayer.frame = CGRect(origin: .zero, size: size.cg)
        mediaLayer.transform = flipsContents ? CATransform3DMakeScale(1, -1, 1) : CATransform3DIdentity
        if let image {
            if (mediaLayer.contents as AnyObject?) !== image { mediaLayer.contents = image }
            mediaLayer.backgroundColor = nil
        } else {
            mediaLayer.contents = nil
            mediaLayer.backgroundColor = CGColor(gray: 0.5, alpha: 1)
        }
    }

    private func clearText() {
        for l in textLayers { l.removeFromSuperlayer() }
        textLayers = []
        textKeys = [nil, nil]
        textImages = [nil, nil]
    }

    /// Draws the current text, and the previous one during a swap, each at
    /// its point in its transition. Each text keeps its own box, placed in
    /// the layer's by the alignment, so the old and new line up as they
    /// would in the design.
    private func updateText(_ text: ResolvedText, size: Size2) {
        if textLayers.isEmpty {
            textLayers = (0..<2).map { _ in
                let l = CALayer()
                l.actions = Self.noActions
                l.contentsScale = scale
                return l
            }
            container.sublayers = textLayers
        }
        let width = text.sizing == .fixedWidth ? size.width : nil
        let swap = text.swap
        let texts = [swap?.previous, text.text]
        for (i, string) in texts.enumerated() {
            let layer = textLayers[i]
            // How far this text is through its transition, and which one.
            let progress: Double, transition: TextTransition, leaving: Bool
            if i == 0 {
                guard let swap, swap.outProgress < 1 else { layer.isHidden = true; continue }
                progress = swap.outProgress
                transition = swap.transitionOut
                leaving = true
            } else {
                if let swap, swap.inProgress <= 0 { layer.isHidden = true; continue }
                progress = swap?.inProgress ?? 1
                transition = swap?.transitionIn ?? .none
                leaving = false
            }
            guard let string else { layer.isHidden = true; continue }
            layer.isHidden = false
            let key = TextImage.Key(text: string, style: text.style, color: text.color, width: width, scale: scale)
            if textKeys[i] != key {
                textKeys[i] = key
                textImages[i] = TextImage(key)
                layer.contents = textImages[i]?.image
                layer.contentsScale = scale
            }
            guard let image = textImages[i] else { continue }
            let x: Double
            switch text.alignment {
            case .left, .justified: x = 0
            case .center: x = (size.width - image.box.width) / 2
            case .right: x = size.width - image.box.width
            }
            layer.transform = CATransform3DIdentity
            let turn = flipsContents ? CATransform3DMakeScale(1, -1, 1) : CATransform3DIdentity
            layer.frame = CGRect(x: x - image.margin, y: -image.margin,
                                 width: image.box.width + image.margin * 2, height: image.box.height + image.margin * 2)
            // Leaving goes from nothing done (0) to gone (1); arriving from
            // not there (0) to settled (1). Both read as one amount, `shown`.
            let shown = leaving ? 1 - progress : progress
            let distance = text.fontSize
            var effect = CATransform3DIdentity
            switch transition {
            case .none:
                layer.opacity = 1
            case .fade:
                layer.opacity = Float(shown)
            case .slide:
                layer.opacity = Float(shown)
                // Up and away when leaving, up from below when arriving.
                let dy = leaving ? -distance * progress : distance * (1 - progress)
                effect = CATransform3DMakeTranslation(0, dy, 0)
            case .scale:
                layer.opacity = Float(shown)
                let s = 0.6 + 0.4 * shown
                effect = CATransform3DMakeScale(s, s, 1)
            }
            layer.transform = CATransform3DConcat(turn, effect)
        }
    }

    private func clearPaint() {
        for p in paintLayers { p.root.removeFromSuperlayer() }
        paintLayers = []
        signature = []
    }

    private func updateShape(_ shape: ResolvedShape, size: Size2) {
        let wanted = shape.fills.map { "fill-" + $0.kind } + shape.strokes.map { "stroke-" + $0.paint.kind + "-" + $0.alignment.rawValue }
        if wanted != signature {
            clearPaint()
            paintLayers = shape.fills.map { PaintLayers(paint: $0, stroke: nil, scale: scale) }
                + shape.strokes.map { PaintLayers(paint: $0.paint, stroke: $0, scale: scale) }
            // The backdrop, if any, goes back underneath in `updateBackdrop`.
            container.sublayers = paintLayers.map(\.root)
            signature = wanted
        }
        let path = shape.path.cgPath
        let bounds = CGRect(origin: .zero, size: size.cg)
        for (i, fill) in shape.fills.enumerated() {
            paintLayers[i].update(paint: fill, stroke: nil, path: path, bounds: bounds)
        }
        for (i, stroke) in shape.strokes.enumerated() {
            paintLayers[shape.fills.count + i].update(paint: stroke.paint, stroke: stroke, path: path, bounds: bounds)
        }
    }
}

// MARK: - One fill or stroke

/// The layers that draw one fill or one stroke.
///
/// A solid fill is one shape layer. A gradient is a gradient layer masked by
/// the shape. A stroke sits inside a wrapper whose mask trims it to the inside
/// or outside of the path, which is how Core Animation, which only strokes
/// centred on the path, gets the other two alignments: the stroke is drawn at
/// twice the width and half of it is masked away.
private final class PaintLayers {
    let root = CALayer()
    private let shape = CAShapeLayer()
    private var gradient: CAGradientLayer?
    private let alignmentMask = CAShapeLayer()

    init(paint: ResolvedPaint, stroke: ResolvedStroke?, scale: CGFloat) {
        for layer in [root, shape, alignmentMask] {
            layer.anchorPoint = .zero
            layer.actions = Node.noActions
        }
        if paint.kind == "solid" {
            root.addSublayer(shape)
        } else {
            let g = CAGradientLayer()
            g.anchorPoint = .zero
            g.actions = Node.noActions
            g.mask = shape
            root.addSublayer(g)
            gradient = g
        }
        if let stroke, stroke.alignment != .center {
            alignmentMask.fillColor = CGColor(gray: 0, alpha: 1)
            root.mask = alignmentMask
        }
        setContentsScale(scale)
    }

    func setContentsScale(_ scale: CGFloat) {
        for layer in [root, shape, alignmentMask] { layer.contentsScale = scale }
        gradient?.contentsScale = scale
    }

    func update(paint: ResolvedPaint, stroke: ResolvedStroke?, path: CGPath, bounds: CGRect) {
        root.frame = bounds
        shape.frame = bounds
        shape.path = path

        // The shape is either the visible paint (solid) or the gradient's mask,
        // in which case only its coverage matters and it is drawn in black.
        let ink: CGColor
        if case .solid(let color) = paint { ink = color.cgColor } else { ink = CGColor(gray: 0, alpha: 1) }

        if let stroke {
            let doubled = stroke.alignment != .center
            shape.fillColor = nil
            shape.strokeColor = ink
            shape.lineWidth = stroke.width * (doubled ? 2 : 1)
            shape.lineCap = stroke.cap.ca
            shape.lineJoin = stroke.join.ca
            shape.lineDashPattern = stroke.dashPattern.isEmpty ? nil : stroke.dashPattern.map { NSNumber(value: $0) }
            shape.lineDashPhase = stroke.dashOffset
            shape.strokeStart = stroke.trimStart
            shape.strokeEnd = stroke.trimEnd
            if doubled {
                alignmentMask.frame = bounds
                if stroke.alignment == .inside {
                    alignmentMask.fillRule = .nonZero
                    alignmentMask.path = path
                } else {
                    // Everything except the shape: a rectangle well beyond the
                    // stroke, with the shape cut out of it.
                    let outside = CGMutablePath()
                    let reach = stroke.width * 4 + 8
                    outside.addRect(path.boundingBoxOfPath.insetBy(dx: -reach, dy: -reach))
                    outside.addPath(path)
                    alignmentMask.fillRule = .evenOdd
                    alignmentMask.path = outside
                }
            }
        } else {
            shape.fillColor = ink
            shape.strokeColor = nil
        }

        guard let gradient else { return }
        // A gradient's box is the layer's box, or the stroke's reach for a
        // stroke, so a stroke's gradient does not stop at the layer's edge.
        let reach = stroke.map { $0.width * 2 } ?? 0
        let box = bounds.insetBy(dx: -reach, dy: -reach)
        gradient.frame = box
        shape.frame = CGRect(x: -box.minX, y: -box.minY, width: bounds.width, height: bounds.height)
        func unit(_ p: Vec2) -> CGPoint {
            CGPoint(x: box.width > 0 ? (p.x - box.minX) / box.width : 0.5,
                    y: box.height > 0 ? (p.y - box.minY) / box.height : 0.5)
        }
        switch paint {
        case .linear(let stops, let start, let end):
            gradient.type = .axial
            gradient.colors = stops.map(\.color.cgColor)
            gradient.locations = stops.map { NSNumber(value: $0.position) }
            gradient.startPoint = unit(start)
            gradient.endPoint = unit(end)
        case .radial(let stops, let center, let radius):
            gradient.type = .radial
            gradient.colors = stops.map(\.color.cgColor)
            gradient.locations = stops.map { NSNumber(value: $0.position) }
            gradient.startPoint = unit(center)
            gradient.endPoint = unit(Vec2(center.x + radius, center.y + radius))
        case .solid:
            break
        }
    }
}

// MARK: - Conversions

extension ResolvedPaint {
    var kind: String {
        switch self {
        case .solid: return "solid"
        case .linear: return "linear"
        case .radial: return "radial"
        }
    }
}

extension Affine {
    /// The same transform as a Core Animation matrix. Core Animation multiplies
    /// row vectors, so `a`, `c`, `tx` produce x and `b`, `d`, `ty` produce y,
    /// matching `Affine.apply`.
    var caTransform: CATransform3D {
        var m = CATransform3DIdentity
        m.m11 = a
        m.m12 = b
        m.m21 = c
        m.m22 = d
        m.m41 = tx
        m.m42 = ty
        return m
    }
}

extension LineCap {
    var ca: CAShapeLayerLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

extension LineJoin {
    var ca: CAShapeLayerLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
