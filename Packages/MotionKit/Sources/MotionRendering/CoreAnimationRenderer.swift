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
/// carrying its transform, opacity, shadow, blur and mask; a group's
/// children sit in a holder inside that container, which clips them and is
/// what makes group opacity and group transforms apply to the children as
/// one picture. A frame's fills go under the holder and its strokes over it.
public final class CoreAnimationRenderer: SceneRenderer {
    /// The composition, `size` points across with its origin at the top-left.
    /// Put it in a layer whose coordinates run downward (a flipped view, or a
    /// layer with `isGeometryFlipped`) and scale it with a transform to zoom.
    public let rootLayer = CALayer()
    /// The layers, over the composition's background as its own colour. The
    /// background is drawn by this layer rather than by one beside it, so a
    /// layer's blend mode has it to blend with: a blend only sees what is
    /// drawn in its own superlayer.
    private let contentLayer = CALayer()
    private var nodes: [UUID: Node] = [:]
    /// Each masked layer's mask, by the masked layer's id. Kept per masked
    /// layer rather than per mask, since a Core Animation layer can be the
    /// mask of only one other.
    private var masks: [UUID: MaskNode] = [:]

    /// Whether pictures (text now; images and video later) are drawn upside
    /// down and must be turned over. Off screen the layer tree runs y up and
    /// the texture's rows turn it the right way, which shapes never notice
    /// but a picture does. The offscreen renderer turns this on.
    public var flipsContents = false {
        didSet {
            for node in nodes.values { node.flipsContents = flipsContents }
            for mask in masks.values { mask.node.flipsContents = flipsContents }
        }
    }

    /// Where image and video layers get their pictures. Without one they draw
    /// as a grey box, as they do when a file is missing.
    public var media: MediaProvider?

    /// How many device pixels to rasterise per point. Raise it for Retina
    /// screens and high-resolution exports.
    public var contentsScale: CGFloat = 2 {
        didSet {
            for node in nodes.values { node.setContentsScale(contentsScale) }
            for mask in masks.values { mask.node.setContentsScale(contentsScale) }
        }
    }

    public init() {
        for layer in [rootLayer, contentLayer] {
            layer.anchorPoint = .zero
            layer.actions = Node.noActions
        }
        rootLayer.masksToBounds = true
        rootLayer.addSublayer(contentLayer)
    }

    public func render(_ scene: ResolvedScene) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let bounds = CGRect(origin: .zero, size: scene.size.cg)
        if rootLayer.bounds != bounds {
            rootLayer.bounds = bounds
            contentLayer.frame = bounds
        }
        contentLayer.backgroundColor = scene.background?.cgColor

        var seen = Set<UUID>()
        var children: [UUID?: [CALayer]] = [:]
        for resolved in scene.layers {
            let node = nodes[resolved.id] ?? {
                let made = Node(scale: contentsScale)
                made.flipsContents = flipsContents
                nodes[resolved.id] = made
                return made
            }()
            if case .text = resolved.content { node.setTextZoom(Self.textZoom(of: resolved, in: scene, scale: contentsScale)) }
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
            if let node = nodes[resolved.id] { Self.setSublayers(node.children, children[resolved.id] ?? []) }
        }
        updateMasks(scene)
    }

    /// Gives every masked layer its mask, drawn by a node of its own and
    /// placed in the masked layer's space, and takes masks away that have
    /// gone.
    private func updateMasks(_ scene: ResolvedScene) {
        var masked = Set<UUID>()
        for resolved in scene.layers {
            guard let node = nodes[resolved.id] else { continue }
            guard let mask = resolved.mask, let source = scene.mask(mask.layerID) else {
                if node.container.mask != nil { node.container.mask = nil }
                continue
            }
            let made = masks[resolved.id] ?? {
                let m = MaskNode(scale: contentsScale)
                m.node.flipsContents = flipsContents
                masks[resolved.id] = m
                return m
            }()
            if case .text = source.content { made.node.setTextZoom(Self.textZoom(of: source, in: scene, scale: contentsScale)) }
            made.update(source, mask: mask, bounds: node.container.bounds, media: media)
            if node.container.mask !== made.root { node.container.mask = made.root }
            masked.insert(resolved.id)
        }
        for id in masks.keys where !masked.contains(id) { masks[id] = nil }
    }

    /// How much bigger than its own size a text is drawn, through its own
    /// scale and every group's and frame's around it, so its picture can be
    /// drawn that much finer: a text in a frame scaled to 300% was drawn at
    /// its own size and stretched, and came out soft on the canvas and in
    /// exports. Rounded up in steps of about 41% (a half power of two) so a
    /// Scale action draws the text again a handful of times rather than on
    /// every frame, never below 1, and held so the picture stays within
    /// `TextImage.maxSide` pixels.
    static func textZoom(of layer: ResolvedLayer, in scene: ResolvedScene, scale: CGFloat) -> CGFloat {
        guard let w = scene.worldTransform(of: layer.id) else { return 1 }
        let stretch = max(hypot(w.a, w.b), hypot(w.c, w.d))
        guard stretch.isFinite, stretch > 1.001 else { return 1 }
        let stepped = pow(2, (log2(stretch) * 2).rounded(.up) / 2)
        let side = max(layer.size.width, layer.size.height, 1)
        return CGFloat(max(1, min(stepped, TextImage.maxSide / (side * max(Double(scale), 1)))))
    }

    /// Only touches the tree when the order actually changed.
    private static func setSublayers(_ parent: CALayer, _ layers: [CALayer]) {
        let current = parent.sublayers ?? []
        if current.count == layers.count && zip(current, layers).allSatisfy({ $0 === $1 }) { return }
        parent.sublayers = layers
    }
}

// MARK: - A mask

/// The layer a mask is set to: the mask layer, drawn as it would be on its
/// own and moved into the masked layer's space. Core Animation keeps the
/// masked layer where this is opaque. Inverted, it is an opaque sheet with
/// the mask layer punched out of it, so the masked layer shows everywhere
/// the mask does not draw.
private final class MaskNode {
    let root = CALayer()
    let node: Node
    private var sheet: CALayer?

    init(scale: CGFloat) {
        node = Node(scale: scale)
        node.ignoresBlend = true
        root.anchorPoint = .zero
        root.actions = Node.noActions
        root.addSublayer(node.container)
    }

    func update(_ source: ResolvedLayer, mask: ResolvedMask, bounds: CGRect, media: MediaProvider?) {
        root.frame = bounds
        node.update(source, media: media)
        node.container.transform = mask.transform.caTransform
        if mask.isInverted, let punch = Compositing.destinationOut() {
            if sheet == nil {
                let made = CALayer()
                made.actions = Node.noActions
                made.backgroundColor = CGColor(gray: 0, alpha: 1)
                root.insertSublayer(made, at: 0)
                sheet = made
                node.container.compositingFilter = punch
            }
            // Wide enough to cover a shadow or a blur spilling past the box.
            sheet?.frame = bounds.insetBy(dx: -4096, dy: -4096)
        } else if let sheet {
            sheet.removeFromSuperlayer()
            self.sheet = nil
            node.container.compositingFilter = nil
        }
    }
}

// MARK: - One layer

final class Node {
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
    /// A group's children, set by the renderer. Clipping happens here rather
    /// than on the container, so a clipping group keeps its shadow, and a
    /// frame clips to its own rounded outline.
    let children = CALayer()
    private let clipMask = CAShapeLayer()
    var flipsContents = false {
        didSet {
            last = nil
            // Picture fills are built the right way up for one or the other.
            if !signature.isEmpty { clearPaint() }
        }
    }
    /// The layer as it was last drawn. A frame where it has not changed
    /// leaves it alone: in a busy scene most layers are still at any moment,
    /// and during a drag only one moves.
    private var last: ResolvedLayer?
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
    private var backdropShown = false
    /// A shape's or frame's drop shadows, each a layer that draws only its
    /// shadow, from the outline, with the shape itself cut out of it; and
    /// its inner shadows, over its fills.
    private var shadowLayers: [ShadowLayer] = []
    /// The outline shadows were last cast from, and the look it came from,
    /// so a layer that only moves or fades never works it out again.
    /// The sublayers `arrange` last set, and what they were made of.
    private var arranged: [CALayer] = []
    private var arrangedShape: [Int] = []
    /// Counts the times the fills and strokes are built afresh, which
    /// changes the layers without changing their number.
    private var rebuilds = 0
    private var outlineLook: ResolvedShape?
    private var outlinePath: CGPath?
    private var innerShadowLayers: [InnerShadowLayer] = []
    /// The last shape's area, which for an even-odd path is a boolean
    /// operation: shapes with a picture are updated every frame, still or
    /// not, and worked this out again for their inner shadows and backdrop.
    private var areaCache: (shape: ResolvedShape, area: CGPath)?

    private func area(of shape: ResolvedShape) -> CGPath {
        if let areaCache, areaCache.shape == shape { return areaCache.area }
        let area = shape.area
        areaCache = (shape, area)
        return area
    }
    /// A mask's own node leaves its compositing to the mask, whatever the
    /// mask layer's blend mode.
    var ignoresBlend = false
    private var blend: BlendMode = .normal
    /// A text layer's words: the current text, and the previous one while a
    /// Counter or Change Text moves from one to the other.
    private var textLayers: [CALayer] = []
    private var textKeys: [TextImage.Key?] = [nil, nil]
    private var textImages: [TextImage?] = [nil, nil]
    /// How much bigger than its own size the text shows (see
    /// `CoreAnimationRenderer.textZoom`); its pictures are drawn that much
    /// finer than `scale`.
    private var textZoom: CGFloat = 1
    private var textScale: CGFloat { scale * textZoom }
    /// A video layer's frame.
    private var mediaLayer: CALayer?
    /// While a text preset moves a text's letters, words or lines one by
    /// one, each of them, and the pictures they are drawn from.
    private var unitLayers: [TextUnitLayer] = []
    private var unitImages: [UnitImageKey: TextImage] = [:]
    /// Made the first time a Mask preset clips the layer: a holder as big as
    /// the part that shows, clipping, around the layer's own sublayers.
    private var revealClip: CALayer?
    private var revealContent: CALayer?
    /// Made the first time motion blur draws the layer: copies of all it
    /// draws, averaged (see `MotionCopies`).
    private var motionCopies: MotionCopies?
    /// What the layer draws into: inside the copies once there are any.
    private var root: CALayer { motionCopies?.body ?? container }
    /// Where the layer's own sublayers go: inside the reveal once there is one.
    private var host: CALayer { revealContent ?? root }

    init(scale: CGFloat) {
        self.scale = scale
        container.anchorPoint = .zero
        container.position = .zero
        container.allowsGroupOpacity = true
        container.actions = Self.noActions
        for l in [children, clipMask] {
            l.anchorPoint = .zero
            l.actions = Self.noActions
        }
        clipMask.fillColor = CGColor(gray: 0, alpha: 1)
    }

    func setContentsScale(_ scale: CGFloat) {
        self.scale = scale
        last = nil
        container.contentsScale = scale
        for p in paintLayers { p.setContentsScale(scale) }
        // Text is a picture drawn at a scale, so it is drawn again.
        textKeys = [nil, nil]
    }

    func setTextZoom(_ zoom: CGFloat) {
        guard zoom != textZoom else { return }
        textZoom = zoom
        last = nil
        textKeys = [nil, nil]
    }

    func update(_ layer: ResolvedLayer, media: MediaProvider?) {
        // Pictures and video may arrive from the media library after the
        // layer first asks, so they are always looked at again.
        switch layer.content {
        case .video: last = nil
        case .shape(let shape) where shape.fills.contains(where: \.isImage): last = nil
        case .group where layer.frame?.fills.contains(where: \.isImage) == true: last = nil
        default:
            if layer == last { return }
            last = layer
        }
        container.bounds = CGRect(origin: .zero, size: layer.size.cg)
        // The anchor point stays at the layer's origin and the whole local
        // transform goes in the matrix, so a layer of zero width or height
        // (a line) still turns about its real anchor.
        container.transform = (layer.motion.placed ?? layer.projection).caTransform
        container.opacity = Float(layer.opacity)
        updateMotion(layer.motion, size: layer.size)

        if !ignoresBlend, layer.blendMode != blend {
            blend = layer.blendMode
            container.compositingFilter = Blending.filter(for: blend)
        }

        // A shape or frame that draws something casts every shadow from its
        // outline, worked out only when there is a shadow to cast. Anything
        // else casts its first shadow from all it draws.
        let fromOutline = layer.look.map { !$0.fills.isEmpty || !$0.strokes.isEmpty } ?? false
        let outline = fromOutline && !layer.shadows.isEmpty ? cachedOutline(layer) : nil
        updateShadowLayers(outline == nil ? [] : layer.shadows, outline: outline,
                           strength: outline == nil ? 1 : layer.look.map(Self.strength) ?? 1)

        // Blur amounts arrive as Figma measures them, twice the Gaussian's
        // standard deviation. Core Animation's shadow radius is the standard
        // deviation, as is the blur filter's radius.
        if !fromOutline, let shadow = layer.shadow {
            container.shadowColor = shadow.color.cgColor
            container.shadowOffset = CGSize(width: shadow.offset.x, height: shadow.offset.y)
            container.shadowRadius = shadow.blur / 2
            container.shadowOpacity = Float(shadow.opacity)
            // Text, video and groups have no outline to spread.
            container.shadowPath = nil
        } else {
            container.shadowOpacity = 0
            container.shadowPath = nil
        }

        if layer.blur != blurRadius {
            blurRadius = layer.blur
            container.filters = layer.blur > 0 ? [Blur.filter(amount: layer.blur)] : nil
        }
        updateReveal(layer.reveal, size: layer.size)

        switch layer.content {
        case .shape(let shape):
            updateShape(shape, size: layer.size, media: media)
            updateBackdrop(layer.backgroundBlur, shape: shape, size: layer.size)
            updateInnerShadows(layer.innerShadows, shape: shape, strength: layer.innerShadows.isEmpty ? 1 : Self.strength(shape),
                               size: layer.size)
            arrange(fills: shape.fills.count, middle: nil)
        case .group:
            if let frame = layer.frame {
                updateShape(frame, size: layer.size, media: media)
                updateBackdrop(layer.backgroundBlur, shape: frame, size: layer.size)
                updateInnerShadows(layer.innerShadows, shape: frame, strength: layer.innerShadows.isEmpty ? 1 : Self.strength(frame),
                                   size: layer.size)
                arrange(fills: frame.fills.count, middle: children)
            } else {
                if !signature.isEmpty { clearPaint() }
                backdropShown = false
                updateInnerShadows([], shape: nil, strength: 1, size: layer.size)
                arrange(fills: 0, middle: children)
            }
            updateClip(layer)
        case .text(let text):
            if !signature.isEmpty { clearPaint() }
            updateText(text, size: layer.size)
        case .video(let id, let time, let fit):
            if !signature.isEmpty { clearPaint() }
            updateMedia(media?.videoFrame(id, at: time), size: layer.size, fit: fit)
        }
        if case .text = layer.content {} else if !textLayers.isEmpty { clearText() }
        switch layer.content {
        case .video: break
        default:
            mediaLayer?.removeFromSuperlayer()
            mediaLayer = nil
        }
    }

    /// The layer's own sublayers in drawing order: drop shadows, the
    /// frosted backdrop, fills, inner shadows, a frame's children, strokes.
    /// Only touches the tree when that order changed.
    private func arrange(fills: Int, middle: CALayer?) {
        // What is built, in counts: when none of it changed since the last
        // time, neither did the order, which is most frames.
        let shape = [paintLayers.count, fills, shadowLayers.count, innerShadowLayers.count, backdropShown ? 1 : 0,
                     middle == nil ? 0 : 1, rebuilds]
        if shape == arrangedShape { return }
        arrangedShape = shape
        let roots = paintLayers.map(\.root)
        var wanted: [CALayer] = shadowLayers.map(\.layer)
        if backdropShown, let backdrop { wanted.append(backdrop) }
        wanted += roots.prefix(fills)
        wanted += innerShadowLayers.map(\.holder)
        if let middle { wanted.append(middle) }
        wanted += roots.dropFirst(fills)
        // Compared with what was last set rather than read back, which
        // copies the list out of Core Animation every frame.
        if arranged.count != wanted.count || !zip(arranged, wanted).allSatisfy({ $0 === $1 }) {
            host.sublayers = wanted
            arranged = wanted
        }
    }

    private func cachedOutline(_ layer: ResolvedLayer) -> CGPath? {
        if let look = layer.look, look == outlineLook, let outlinePath { return outlinePath }
        outlineLook = layer.look
        outlinePath = Self.outline(of: layer)
        return outlinePath
    }

    /// What a shape or frame covers, fills and strokes together, to cast its
    /// shadows from. Nil for anything else, and for a shape or frame that
    /// draws nothing, whose shadows (a frame's children's) come from what is
    /// drawn instead.
    private static func outline(of layer: ResolvedLayer) -> CGPath? {
        guard let shape = layer.look, !shape.fills.isEmpty || !shape.strokes.isEmpty else { return nil }
        let path = shape.area
        var covered: CGPath? = shape.isClosed && !shape.fills.isEmpty ? path : nil
        for stroke in shape.strokes where stroke.width > 0 {
            let dashed = stroke.dashPattern.isEmpty ? path
                : path.copy(dashingWithPhase: stroke.dashOffset, lengths: stroke.dashPattern.map { CGFloat($0) })
            let doubled = stroke.alignment != .center
            var band = dashed.copy(strokingWithWidth: stroke.width * (doubled ? 2 : 1), lineCap: stroke.cap.cg,
                                   lineJoin: stroke.join.cg, miterLimit: 10)
            if stroke.alignment == .inside { band = band.intersection(path) }
            if stroke.alignment == .outside { band = band.subtracting(path) }
            covered = covered.map { $0.union(band) } ?? band
        }
        return covered
    }

    /// How strongly a shape's shadows show: as strongly as its most solid
    /// fill, so a see-through card casts a faint shadow, as in Figma, even
    /// with a solid edge (the fill covers far more); a shape with only
    /// strokes, as its most solid stroke.
    private static func strength(_ shape: ResolvedShape) -> Double {
        let paints = shape.fills.isEmpty ? shape.strokes.map(\.paint) : shape.fills
        return paints.map { paint -> Double in
            switch paint {
            case .solid(let c): return c.a
            case .linear(let stops, _, _), .radial(let stops, _, _): return stops.map(\.color.a).max() ?? 0
            case .image(let image): return image.opacity
            }
        }.max() ?? 1
    }

    private func updateShadowLayers(_ shadows: [ResolvedShadow], outline: CGPath?, strength: Double) {
        while shadowLayers.count > shadows.count { shadowLayers.removeLast().layer.removeFromSuperlayer() }
        while shadowLayers.count < shadows.count { shadowLayers.append(ShadowLayer(scale: scale)) }
        guard let outline else { return }
        let bounds = container.bounds
        for (layer, shadow) in zip(shadowLayers, shadows) {
            layer.update(shadow, outline: outline, strength: strength, bounds: bounds)
        }
    }

    private func updateInnerShadows(_ shadows: [ResolvedShadow], shape: ResolvedShape?, strength: Double, size: Size2) {
        let list = shape?.isClosed == true ? shadows : []
        while innerShadowLayers.count > list.count { innerShadowLayers.removeLast().holder.removeFromSuperlayer() }
        while innerShadowLayers.count < list.count { innerShadowLayers.append(InnerShadowLayer(scale: scale)) }
        guard let shape, !list.isEmpty else { return }
        let path = area(of: shape)
        for (layer, shadow) in zip(innerShadowLayers, list) {
            layer.update(shadow, path: path, strength: strength, bounds: CGRect(origin: .zero, size: size.cg))
        }
    }

    private func updateBackdrop(_ blur: BackgroundBlur?, shape: ResolvedShape, size: Size2) {
        backdropShown = false
        guard let blur else { return }
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
        backdropShown = true
        backdrop.frame = CGRect(origin: .zero, size: size.cg)
        backdropMask.frame = backdrop.bounds
        backdropMask.path = area(of: shape)
        backdrop.opacity = Float(blur.blend)
        if blur.radius != backdropRadius {
            backdropRadius = blur.radius
            backdrop.filters = [Blur.filter(amount: blur.radius)]
        }
    }

    /// The frame covering the layer's box or fitting inside it, centred, or
    /// a grey box where the file is missing, so the layer can still be seen
    /// and picked.
    private func updateMedia(_ image: CGImage?, size: Size2, fit: VideoFit) {
        if mediaLayer == nil {
            let l = CALayer()
            l.actions = Self.noActions
            l.masksToBounds = true
            host.sublayers = [l]
            mediaLayer = l
        }
        guard let mediaLayer else { return }
        let gravity: CALayerContentsGravity = fit == .fill ? .resizeAspectFill : .resizeAspect
        if mediaLayer.contentsGravity != gravity { mediaLayer.contentsGravity = gravity }
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
        clearUnits()
    }

    private func clearUnits() {
        for u in unitLayers { u.holder.removeFromSuperlayer() }
        unitLayers = []
        unitImages = [:]
    }

    /// Each letter, word or line drawn on its own, moved as the text preset
    /// has it. Its picture is the text drawn over just its box, so it lines
    /// up with the rest exactly as the whole text would.
    private func updateUnits(_ text: ResolvedText, size: Size2) {
        let width = text.sizing == .fixedWidth ? size.width : nil
        let key = TextImage.Key(text: text.text, style: text.style, color: text.color, width: width, scale: textScale,
                                showsFill: text.showsFill, stroke: text.stroke)
        if unitImages.keys.first.map({ $0.text != key }) ?? false { unitImages = [:] }
        while unitLayers.count > text.units.count { unitLayers.removeLast().holder.removeFromSuperlayer() }
        while unitLayers.count < text.units.count {
            let made = TextUnitLayer(scale: scale)
            host.addSublayer(made.holder)
            unitLayers.append(made)
        }
        for (layer, unit) in zip(unitLayers, text.units) {
            let imageKey = UnitImageKey(text: key, location: unit.range.location, length: unit.range.length)
            let image = unitImages[imageKey] ?? {
                let made = TextImage(key, unit: (unit.box, unit.range))
                unitImages[imageKey] = made
                return made
            }()
            layer.update(unit, image: image, flips: flipsContents)
        }
    }

    /// Draws the layer as motion blur has it: all it draws, wrapped in copies
    /// while it blurs, and unwrapped again once it stops, so a layer that has
    /// blurred draws exactly as one that never did. The copies draw as one
    /// picture, so a blend mode inside a group blends only within it while
    /// it smears.
    private func updateMotion(_ motion: MotionSpread, size: Size2) {
        guard case .spread = motion else {
            guard let copies = motionCopies else { return }
            container.sublayers = copies.body.sublayers
            motionCopies = nil
            return
        }
        if motionCopies == nil {
            let made = MotionCopies()
            made.body.sublayers = container.sublayers
            container.sublayers = [made.copies]
            motionCopies = made
        }
        motionCopies?.apply(motion, size: size.cg)
    }

    /// Clips the layer to part of its box, with its content moved and
    /// zoomed behind the clip, as a Mask preset has it. The holders are made
    /// the first time and kept, open and still, once the reveal ends.
    private func updateReveal(_ reveal: Reveal, size: Size2) {
        guard reveal != .none || revealClip != nil else { return }
        if revealClip == nil {
            let clip = CALayer(), content = CALayer()
            for l in [clip, content] {
                l.anchorPoint = .zero
                l.actions = Self.noActions
            }
            content.sublayers = root.sublayers
            clip.addSublayer(content)
            root.sublayers = [clip]
            revealClip = clip
            revealContent = content
        }
        guard let revealClip, let revealContent else { return }
        RevealLayers.apply(reveal, size: size.cg, clip: revealClip, content: revealContent)
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
            host.sublayers = textLayers
        }
        guard text.units.isEmpty else {
            for l in textLayers { l.isHidden = true }
            updateUnits(text, size: size)
            return
        }
        if !unitLayers.isEmpty { clearUnits() }
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
            let key = TextImage.Key(text: string, style: text.style, color: text.color, width: width, scale: textScale,
                                    showsFill: text.showsFill, stroke: text.stroke)
            if textKeys[i] != key {
                textKeys[i] = key
                textImages[i] = TextImage(key)
                layer.contents = textImages[i]?.image
                layer.contentsScale = textScale
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

    /// A group's holder sized to its box and clipped as it asks: to the box
    /// for a group, to its outline for a frame.
    private func updateClip(_ layer: ResolvedLayer) {
        children.frame = CGRect(origin: .zero, size: layer.size.cg)
        if layer.clipsContent, let frame = layer.frame {
            children.masksToBounds = false
            clipMask.frame = children.bounds
            clipMask.path = frame.path.cgPath
            if children.mask !== clipMask { children.mask = clipMask }
        } else {
            if children.mask != nil { children.mask = nil }
            children.masksToBounds = layer.clipsContent
        }
    }

    private func updateShape(_ shape: ResolvedShape, size: Size2, media: MediaProvider?) {
        let wanted = shape.fills.map { "fill-" + $0.kind } + shape.strokes.map { "stroke-" + $0.paint.kind + "-" + $0.alignment.rawValue }
        if wanted != signature {
            clearPaint()
            paintLayers = shape.fills.map { PaintLayers(paint: $0, stroke: nil, scale: scale, flipsContents: flipsContents) }
                + shape.strokes.map { PaintLayers(paint: $0.paint, stroke: $0, scale: scale, flipsContents: flipsContents) }
            // Put in place, with everything else the layer draws, by `arrange`.
            signature = wanted
            rebuilds += 1
        }
        let path = shape.path.cgPath
        let bounds = CGRect(origin: .zero, size: size.cg)
        for (i, fill) in shape.fills.enumerated() {
            paintLayers[i].update(paint: fill, stroke: nil, path: path, rule: shape.fillRule.ca, bounds: bounds, media: media)
        }
        for (i, stroke) in shape.strokes.enumerated() {
            paintLayers[shape.fills.count + i].update(paint: stroke.paint, stroke: stroke, path: path, rule: shape.fillRule.ca,
                                                      bounds: bounds, media: media)
        }
    }
}

// MARK: - One fill or stroke

/// The layers that draw one fill or one stroke.
///
/// A solid fill is one shape layer. A gradient is a gradient layer masked by
/// the shape, and so is a picture: its holder, masked by the shape, carries
/// the picture where the fill places it, or for a tiled one, a row of
/// columns of it. A stroke sits inside a wrapper whose mask trims it to the inside
/// or outside of the path, which is how Core Animation, which only strokes
/// centred on the path, gets the other two alignments: the stroke is drawn at
/// twice the width and half of it is masked away.
/// Places a reveal's two holders: the clip, as big as the part of the box
/// that shows and clipping to itself, with its bounds in the layer's own
/// coordinates so what it holds needs no moving; and inside it the content,
/// moved and zoomed about the box's centre.
enum RevealLayers {
    static func apply(_ reveal: Reveal, size: CGSize, clip: CALayer, content: CALayer) {
        let b = reveal.box
        let open = reveal == .none ? CGRect(origin: .zero, size: size)
            : CGRect(x: b.x * size.width, y: b.y * size.height, width: b.width * size.width, height: b.height * size.height)
        clip.masksToBounds = reveal != .none
        clip.bounds = open
        clip.position = open.origin
        content.bounds = CGRect(origin: .zero, size: size)
        content.position = .zero
        let centre = Vec2(size.width / 2, size.height / 2)
        let moved = Affine.translation(Vec2(-centre.x, -centre.y)).then(.scale(Vec2(b.zoom, b.zoom)))
            .then(.translation(Vec2(centre.x + b.dx * size.width, centre.y + b.dy * size.height)))
        content.transform = reveal == .none ? CATransform3DIdentity : moved.caTransform
    }
}

/// Motion blur's copies, for the canvas: a replicator drawing its body
/// `count` times, each copy moved by `step` from the one before, in the
/// body's own space (the replicator turns about its origin, which is the
/// layer's). Each copy is drawn at a share of its strength and added to the
/// rest, so together they are the average of the moments across the
/// shutter, and the replicator draws them as one picture first, so they add
/// to one another and not to what is behind. Still, it is one copy at full
/// strength. Each share is rounded to a whole step of 255 before the copies
/// are added, which with many copies adds up (24 copies of an off-white of
/// 247 came to white), so exports draw each moment whole and average in
/// full precision instead (`OffscreenRenderer`, `MotionSpread.exact`).
final class MotionCopies {
    let copies = CAReplicatorLayer()
    let body = CALayer()

    init() {
        for l in [copies, body] {
            l.anchorPoint = .zero
            l.position = .zero
            l.actions = Node.noActions
            l.allowsGroupOpacity = true
        }
        copies.addSublayer(body)
    }

    func apply(_ motion: MotionSpread, size: CGSize) {
        let bounds = CGRect(origin: .zero, size: size)
        if copies.bounds != bounds {
            copies.bounds = bounds
            body.bounds = bounds
        }
        if case .spread(_, let step, let count) = motion, let add = Compositing.add() {
            copies.instanceCount = count
            copies.instanceTransform = step.caTransform
            body.opacity = 1 / Float(count)
            if body.compositingFilter == nil { body.compositingFilter = add }
            // Just under full, so the copies are drawn together, apart,
            // before they are laid over the rest: a group only forms when
            // it fades.
            copies.opacity = Self.grouped
        } else if copies.instanceCount != 1 || body.compositingFilter != nil {
            copies.instanceCount = 1
            copies.instanceTransform = CATransform3DIdentity
            body.opacity = 1
            body.compositingFilter = nil
            copies.opacity = 1
        }
    }

    /// Fades by a thousandth, which no pixel shows.
    static let grouped: Float = 0.999
}

/// Which picture a letter, word or line is drawn from.
private struct UnitImageKey: Hashable {
    let text: TextImage.Key
    let location: Int
    let length: Int
}

/// One letter, word or line of a text moved by a text preset: a holder
/// placed by its transform, fading and blurring as a whole, and inside it a
/// reveal and the picture.
private final class TextUnitLayer {
    let holder = CALayer()
    /// Each letter blurs by its own motion.
    private let motion = MotionCopies()
    private let clip = CALayer()
    private let content = CALayer()
    private let picture = CALayer()
    private var blur = 0.0

    init(scale: CGFloat) {
        for l in [holder, clip, content, picture] {
            l.anchorPoint = .zero
            l.actions = Node.noActions
        }
        picture.contentsScale = scale
        holder.allowsGroupOpacity = true
        holder.addSublayer(motion.copies)
        motion.body.addSublayer(clip)
        clip.addSublayer(content)
        content.addSublayer(picture)
    }

    func update(_ unit: ResolvedTextUnit, image: TextImage, flips: Bool) {
        let size = CGSize(width: unit.box.width, height: unit.box.height)
        holder.bounds = CGRect(origin: .zero, size: size)
        holder.position = .zero
        holder.transform = (unit.motion.placed ?? unit.transform).caTransform
        motion.apply(unit.motion, size: size)
        holder.opacity = Float(unit.opacity)
        if unit.blur != blur {
            blur = unit.blur
            holder.filters = unit.blur > 0 ? [Blur.filter(amount: unit.blur)] : nil
        }
        RevealLayers.apply(unit.reveal, size: size, clip: clip, content: content)
        if (picture.contents as AnyObject?) !== image.image {
            picture.contents = image.image
            picture.contentsScale = image.scale
        }
        // The picture covers the box and a margin all round it.
        picture.transform = CATransform3DIdentity
        picture.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        picture.frame = CGRect(x: image.origin.x - unit.box.minX, y: image.origin.y - unit.box.minY,
                               width: image.box.width, height: image.box.height)
        picture.transform = flips ? CATransform3DMakeScale(1, -1, 1) : CATransform3DIdentity
    }
}

private final class PaintLayers {
    let root = CALayer()
    private let shape = CAShapeLayer()
    private var gradient: CAGradientLayer?
    private let alignmentMask = CAShapeLayer()
    /// A picture fill: the holder masked by the shape, the picture, and for
    /// a tiled one, the replicators that repeat it across and down.
    private var holder: CALayer?
    private var picture: CALayer?
    private var across: CAReplicatorLayer?
    private var down: CAReplicatorLayer?
    private let flipsContents: Bool

    /// The most tiles drawn along either side, so a tiny tile cannot ask for
    /// millions of copies.
    private static let maxTiles = 256

    init(paint: ResolvedPaint, stroke: ResolvedStroke?, scale: CGFloat, flipsContents: Bool) {
        self.flipsContents = flipsContents
        for layer in [root, shape, alignmentMask] {
            layer.anchorPoint = .zero
            layer.actions = Node.noActions
        }
        if paint.kind == "solid" {
            root.addSublayer(shape)
        } else if case .image(let image) = paint {
            let h = CALayer(), p = CALayer()
            for l in [h, p] { l.actions = Node.noActions }
            h.anchorPoint = .zero
            p.contentsGravity = .resize
            h.mask = shape
            if image.tiles {
                let x = CAReplicatorLayer(), y = CAReplicatorLayer()
                for l in [x, y] {
                    l.anchorPoint = .zero
                    l.actions = Node.noActions
                }
                y.addSublayer(p)
                x.addSublayer(y)
                h.addSublayer(x)
                across = x
                down = y
            } else {
                h.addSublayer(p)
            }
            root.addSublayer(h)
            holder = h
            picture = p
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

    func update(paint: ResolvedPaint, stroke: ResolvedStroke?, path: CGPath, rule: CAShapeLayerFillRule,
                bounds: CGRect, media: MediaProvider?) {
        root.frame = bounds
        shape.frame = bounds
        shape.path = path
        shape.fillRule = rule

        if case .image(let image) = paint {
            updatePicture(image, bounds: bounds, media: media)
            return
        }

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
                    alignmentMask.fillRule = rule
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
        case .solid, .image:
            break
        }
    }
}

extension PaintLayers {
    /// The picture where its fill places it, turned and (off screen) turned
    /// over, inside the shape. A missing file shows grey, so the shape can
    /// still be seen and picked.
    private func updatePicture(_ image: ResolvedImage, bounds: CGRect, media: MediaProvider?) {
        guard let holder, let picture else { return }
        holder.frame = bounds
        shape.fillColor = CGColor(gray: 0, alpha: 1)
        shape.strokeColor = nil
        holder.opacity = Float(image.opacity)
        let cg = media?.image(image.mediaID)
        if (picture.contents as AnyObject?) !== cg { picture.contents = cg }
        holder.backgroundColor = cg == nil ? CGColor(gray: 0.5, alpha: 1) : nil

        let frame = image.frame
        let upright = image.turns % 2 == 1 ? CGSize(width: frame.height, height: frame.width)
                                           : CGSize(width: frame.width, height: frame.height)
        picture.transform = CATransform3DIdentity
        picture.bounds = CGRect(origin: .zero, size: upright)
        picture.position = CGPoint(x: frame.center.x, y: frame.center.y)
        let turn = Affine.rotation(degrees: Double(image.turns) * 90).caTransform
        picture.transform = flipsContents ? CATransform3DConcat(CATransform3DMakeScale(1, -1, 1), turn) : turn

        guard let across, let down, frame.width > 0, frame.height > 0 else { return }
        across.frame = bounds
        down.frame = bounds
        func count(_ length: Double, _ tile: Double) -> Int { min(max(Int((length / tile).rounded(.up)), 1), Self.maxTiles) }
        across.instanceCount = count(bounds.width, frame.width)
        down.instanceCount = count(bounds.height, frame.height)
        across.instanceTransform = CATransform3DMakeTranslation(frame.width, 0, 0)
        down.instanceTransform = CATransform3DMakeTranslation(0, frame.height, 0)
    }
}

// MARK: - Shadows

/// One drop shadow of a shape or frame: a layer drawing nothing but its
/// shadow, cast from the outline, with the outline itself cut out, so it
/// never shows through a see-through fill, as in Figma.
private final class ShadowLayer {
    let layer = CALayer()
    private let knockout = CAShapeLayer()

    init(scale: CGFloat) {
        for l in [layer, knockout] {
            l.anchorPoint = .zero
            l.actions = Node.noActions
            l.contentsScale = scale
        }
        knockout.fillRule = .evenOdd
        knockout.fillColor = CGColor(gray: 0, alpha: 1)
        layer.mask = knockout
    }

    private var drawn: (ResolvedShadow, CGPath, Double, CGRect)?

    func update(_ shadow: ResolvedShadow, outline: CGPath, strength: Double, bounds: CGRect) {
        // A layer that only moves keeps its shadow as it is.
        if let d = drawn, d.0 == shadow, d.1 === outline, d.2 == strength, d.3 == bounds { return }
        drawn = (shadow, outline, strength, bounds)
        layer.frame = bounds
        layer.shadowPath = Shadows.spread(outline, by: shadow.spread)
        layer.shadowColor = shadow.color.cgColor
        layer.shadowOffset = CGSize(width: shadow.offset.x, height: shadow.offset.y)
        layer.shadowRadius = shadow.blur / 2
        layer.shadowOpacity = Float(shadow.opacity * min(max(strength, 0), 1))
        knockout.frame = CGRect(origin: .zero, size: bounds.size)
        let cover = CGMutablePath()
        cover.addRect(Shadows.reach(of: outline, shadow))
        cover.addPath(outline)
        knockout.path = cover
    }
}

/// One inner shadow: inside the outline, a sheet with the outline (shrunk
/// by any spread) cut out of it, casting its shadow inward.
private final class InnerShadowLayer {
    let holder = CALayer()
    private let clip = CAShapeLayer()
    private let caster = CAShapeLayer()

    init(scale: CGFloat) {
        for l in [holder, clip, caster] {
            l.anchorPoint = .zero
            l.actions = Node.noActions
            l.contentsScale = scale
        }
        clip.fillColor = CGColor(gray: 0, alpha: 1)
        holder.mask = clip
        caster.fillRule = .evenOdd
        holder.addSublayer(caster)
    }

    /// What it was last drawn from, so an unchanged shadow is not cut out
    /// again (a spread is a boolean operation on the path).
    private var drawn: (shadow: ResolvedShadow, path: CGPath, strength: Double, bounds: CGRect)?

    func update(_ shadow: ResolvedShadow, path: CGPath, strength: Double, bounds: CGRect) {
        if let drawn, drawn.shadow == shadow, drawn.strength == strength, drawn.bounds == bounds, drawn.path == path { return }
        drawn = (shadow, path, strength, bounds)
        holder.frame = bounds
        clip.frame = holder.bounds
        clip.path = path
        caster.frame = holder.bounds
        // The colour's own alpha and the opacity go on the holder, so the
        // band a spread leaves and the shadow match.
        holder.opacity = Float(shadow.color.a * shadow.opacity * min(max(strength, 0), 1))
        var solid = shadow.color
        solid.a = 1
        let hole = Shadows.spread(path, by: -shadow.spread)
        let sheet = CGMutablePath()
        sheet.addRect(Shadows.reach(of: path, shadow))
        sheet.addPath(hole)
        caster.path = sheet
        caster.fillColor = solid.cgColor
        caster.shadowColor = solid.cgColor
        caster.shadowOpacity = 1
        caster.shadowOffset = CGSize(width: shadow.offset.x, height: shadow.offset.y)
        caster.shadowRadius = shadow.blur / 2
    }
}

private enum Shadows {
    /// An outline grown by `spread`, or shrunk for a negative one.
    static func spread(_ path: CGPath, by spread: Double) -> CGPath {
        guard spread != 0 else { return path }
        let band = path.copy(strokingWithWidth: abs(spread) * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)
        return spread > 0 ? path.union(band) : path.subtracting(band)
    }

    /// Well past everywhere a shadow of the outline can reach.
    static func reach(of path: CGPath, _ shadow: ResolvedShadow) -> CGRect {
        let far = abs(shadow.offset.x) + abs(shadow.offset.y) + shadow.blur * 2 + abs(shadow.spread) + 16
        return path.boundingBoxOfPath.insetBy(dx: -far, dy: -far)
    }
}

/// Figma's blend modes as Core Animation compositing filters: its own
/// private ones where it has them, looked up by name as the blur is, and
/// otherwise Core Image's.
enum Blending {
    static func filter(for mode: BlendMode) -> Any? {
        guard mode != .normal else { return nil }
        if let name = coreAnimationName(mode), let made = PrivateFilter.make(name) { return made }
        return CIFilter(name: coreImageName(mode))
    }

    static func coreAnimationName(_ mode: BlendMode) -> String? {
        switch mode {
        case .normal: return nil
        case .darken: return "darkenBlendMode"
        case .multiply: return "multiplyBlendMode"
        case .linearBurn: return "plusD"
        case .colorBurn: return "colorBurnBlendMode"
        case .lighten: return "lightenBlendMode"
        case .screen: return "screenBlendMode"
        case .linearDodge: return "plusL"
        case .colorDodge: return "colorDodgeBlendMode"
        case .overlay: return "overlayBlendMode"
        case .softLight: return "softLightBlendMode"
        case .hardLight: return "hardLightBlendMode"
        case .difference: return "differenceBlendMode"
        case .exclusion: return "exclusionBlendMode"
        case .hue: return "hueBlendMode"
        case .saturation: return "saturationBlendMode"
        case .color: return "colorBlendMode"
        case .luminosity: return "luminosityBlendMode"
        }
    }

    static func coreImageName(_ mode: BlendMode) -> String {
        switch mode {
        case .normal: return "CISourceOverCompositing"
        case .darken: return "CIDarkenBlendMode"
        case .multiply: return "CIMultiplyBlendMode"
        case .linearBurn: return "CILinearBurnBlendMode"
        case .colorBurn: return "CIColorBurnBlendMode"
        case .lighten: return "CILightenBlendMode"
        case .screen: return "CIScreenBlendMode"
        case .linearDodge: return "CILinearDodgeBlendMode"
        case .colorDodge: return "CIColorDodgeBlendMode"
        case .overlay: return "CIOverlayBlendMode"
        case .softLight: return "CISoftLightBlendMode"
        case .hardLight: return "CIHardLightBlendMode"
        case .difference: return "CIDifferenceBlendMode"
        case .exclusion: return "CIExclusionBlendMode"
        case .hue: return "CIHueBlendMode"
        case .saturation: return "CISaturationBlendMode"
        case .color: return "CIColorBlendMode"
        case .luminosity: return "CILuminosityBlendMode"
        }
    }
}

// MARK: - Conversions

extension ResolvedShape {
    /// What the shape covers as a path that is inside by winding round:
    /// an even-odd path, holes and all, turned into one that needs no
    /// rule, for cutting and joining with others.
    var area: CGPath {
        let cg = path.cgPath
        return fillRule == .evenOdd ? cg.normalized(using: .evenOdd) : cg
    }
}

extension FillRule {
    var ca: CAShapeLayerFillRule { self == .evenOdd ? .evenOdd : .nonZero }
    public var cg: CGPathFillRule { self == .evenOdd ? .evenOdd : .winding }
}

extension ResolvedPaint {
    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    var kind: String {
        switch self {
        case .solid: return "solid"
        case .linear: return "linear"
        case .radial: return "radial"
        case .image(let image): return image.tiles ? "tiles" : "image"
        }
    }
}

extension Projective {
    /// The same transform as a Core Animation matrix, on the flat plane the
    /// layer is drawn in: the perspective row becomes its fourth column.
    public var caTransform: CATransform3D {
        var m = CATransform3DIdentity
        m.m11 = a
        m.m12 = b
        m.m14 = px
        m.m21 = c
        m.m22 = d
        m.m24 = py
        m.m41 = tx
        m.m42 = ty
        m.m44 = w
        return m
    }
}

extension Affine {
    /// The same transform as a Core Animation matrix. Core Animation multiplies
    /// row vectors, so `a`, `c`, `tx` produce x and `b`, `d`, `ty` produce y,
    /// matching `Affine.apply`.
    public var caTransform: CATransform3D {
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

extension LineCap {
    var cg: CGLineCap {
        switch self {
        case .butt: return .butt
        case .round: return .round
        case .square: return .square
        }
    }
}

extension LineJoin {
    var cg: CGLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }

    var ca: CAShapeLayerLineJoin {
        switch self {
        case .miter: return .miter
        case .round: return .round
        case .bevel: return .bevel
        }
    }
}
