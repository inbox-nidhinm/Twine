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
                nodes[resolved.id] = made
                return made
            }()
            node.update(resolved)
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
        "lineDashPattern": NSNull(), "lineDashPhase": NSNull(), "masksToBounds": NSNull(), "hidden": NSNull(),
    ]

    let container = CALayer()
    private var scale: CGFloat
    /// The kinds of fill and stroke layers currently built, so they are only
    /// rebuilt when a paint changes kind rather than on every frame.
    private var signature: [String] = []
    private var paintLayers: [PaintLayers] = []
    private var blurRadius = 0.0

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
    }

    func update(_ layer: ResolvedLayer) {
        container.bounds = CGRect(origin: .zero, size: layer.size.cg)
        // The anchor point stays at the layer's origin and the whole local
        // transform goes in the matrix, so a layer of zero width or height
        // (a line) still turns about its real anchor.
        container.transform = layer.transform.caTransform
        container.opacity = Float(layer.opacity)
        container.masksToBounds = layer.clipsContent

        if let shadow = layer.shadow {
            container.shadowColor = shadow.color.cgColor
            container.shadowOffset = CGSize(width: shadow.offset.x, height: shadow.offset.y)
            container.shadowRadius = shadow.blur
            container.shadowOpacity = Float(shadow.opacity)
        } else {
            container.shadowOpacity = 0
        }

        if layer.blur != blurRadius {
            blurRadius = layer.blur
            container.filters = layer.blur > 0
                ? [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: layer.blur])!]
                : nil
        }

        switch layer.content {
        case .shape(let shape):
            updateShape(shape, size: layer.size)
        case .group:
            // A group's sublayers are its children, set by the renderer.
            if !signature.isEmpty { clearPaint() }
        case .text, .image, .video:
            // Drawn from milestones 6 and 7.
            if !signature.isEmpty { clearPaint() }
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
