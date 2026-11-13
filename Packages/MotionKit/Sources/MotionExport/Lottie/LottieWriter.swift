import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MotionModel
import MotionEvaluation
import MotionRendering

/// What a Lottie export could not carry over, in words for the export
/// panel: Lottie players draw no blur, shadows, glass, video or perspective,
/// so those are left out and named.
public enum LottieOmission: String, CaseIterable, Sendable {
    case shadows = "Shadows"
    case blur = "Blur"
    case backgroundBlur = "Background blur"
    case glass = "Glass"
    case motionBlur = "Motion blur"
    case pageCurls = "Page curls"
    case depth = "3D, tilt and bend"
    case order = "Changing layer order"
    case video = "Video"
    case angularGradients = "Angular gradients"
    case ovalGradients = "Oval radial gradients"
    case tiledPictures = "Tiled pictures"
    case pictureStrokes = "Picture strokes"
    case linearBurn = "Linear Burn"
}

/// A picture a Lottie carries, as a PNG or JPEG file's bytes.
struct LottieImage {
    var id: String
    var width: Int
    var height: Int
    var data: Data
    var fileExtension: String
}

/// Writes a project as a Lottie animation.
///
/// Every frame is worked out by `evaluate`, exactly as a movie export
/// would, and recorded. Each Twine layer then becomes one or more Lottie
/// layers placed in the composition's own space (`world`), whose
/// properties are those recordings thinned to the keyframes a straight line
/// cannot stand in for (`Series`). Groups need no Lottie layer of their own
/// unless they must be drawn as one picture (an opacity under 100%, a blend
/// mode, a clip, a mask or a Mask preset), when they become precomps the
/// composition's size, so nothing they hold is cut off.
final class LottieWriter {
    private let project: Project
    private let timing: ExportTiming
    private let library: MediaLibrary
    private let media: [UUID: URL]
    /// Pictures carried in the file (base64 in the JSON) or beside it (in a
    /// dotLottie).
    private let embedsImages: Bool
    private var frameCount: Int { timing.frameCount }

    private var recordings: [UUID: Recording] = [:]
    /// Where each layer is drawn among its siblings at the first frame.
    private var rank: [UUID: Int] = [:]
    private var omissions = Set<LottieOmission>()
    private var comps: [(id: String, name: String, plans: [Plan])] = []
    private(set) var images: [LottieImage] = []
    private var imageIDs: [UUID: Int] = [:]
    private var outlines: [LottieText.Key: (path: BezierPath, size: Size2)] = [:]

    init(project: Project, timing: ExportTiming, media: [UUID: URL], library: MediaLibrary, embedsImages: Bool) {
        self.project = project
        self.timing = timing
        self.media = media
        self.library = library
        self.embedsImages = embedsImages
    }

    /// What was left out, in a fixed order.
    var leftOut: [String] { LottieOmission.allCases.filter(omissions.contains).map(\.rawValue) }

    // MARK: Recording

    /// One layer as it is at each frame: an index into `values` (or -1 where
    /// it is not drawn), so a layer that does not change is kept once.
    final class Recording {
        var frames: [Int32]
        var values: [Sample] = []

        init(count: Int) { frames = Array(repeating: -1, count: count) }

        func at(_ f: Int) -> Sample? {
            let i = frames[f]
            return i < 0 ? nil : values[Int(i)]
        }

        func record(_ sample: Sample, at f: Int) {
            if let last = values.last, last == sample {
                frames[f] = Int32(values.count - 1)
            } else {
                values.append(sample)
                frames[f] = Int32(values.count - 1)
            }
        }

        var all: [Sample] { values }
    }

    struct Sample: Equatable {
        var layer: ResolvedLayer
        /// From the layer's own space into the composition's, drawn flat;
        /// nil when it is turned away past the viewer.
        var world: Affine?
    }

    private func record(job: ExportJob, progress: (Double) -> Void) throws {
        let cache = EvaluationCache()
        var firstOrder: [UUID]?
        for f in 0..<frameCount {
            if job.isCancelled { throw ExportError.cancelled }
            let scene = evaluate(project, at: timing.time(ofFrame: f), cache: cache)
            for layer in scene.layers {
                let world = scene.worldProjection(of: layer.id).flatMap { LottieGeometry.flat($0, over: layer.size) }
                recording(layer.id).record(Sample(layer: layer, world: world), at: f)
                note(layer)
            }
            for mask in scene.masks {
                recording(mask.id).record(Sample(layer: mask, world: nil), at: f)
                note(mask)
            }
            let order = scene.drawingOrder().map { scene.layers[$0].id }
            if let firstOrder {
                if order != firstOrder.filter(Set(order).contains) { omissions.insert(.order) }
            } else {
                firstOrder = order
                for (i, id) in order.enumerated() { rank[id] = i }
            }
            progress(Double(f + 1) / Double(frameCount) * 0.8)
        }
    }

    private func recording(_ id: UUID) -> Recording {
        if let r = recordings[id] { return r }
        let made = Recording(count: frameCount)
        recordings[id] = made
        return made
    }

    /// Notes what a layer has that a Lottie cannot draw.
    private func note(_ layer: ResolvedLayer) {
        if !layer.shadows.isEmpty || !layer.innerShadows.isEmpty { omissions.insert(.shadows) }
        if layer.blur > 0 { omissions.insert(.blur) }
        if layer.backgroundBlur != nil { omissions.insert(.backgroundBlur) }
        if layer.glass != .none { omissions.insert(.glass) }
        if layer.curl != .none { omissions.insert(.pageCurls) }
        if layer.motion != .none { omissions.insert(.motionBlur) }
        if layer.placed != .none || layer.warp.tilt.isTilted || layer.warp.bend != .zero { omissions.insert(.depth) }
        if layer.blendMode == .linearBurn { omissions.insert(.linearBurn) }
        switch layer.content {
        case .video: omissions.insert(.video)
        case .text(let t):
            for unit in t.units {
                if unit.blur > 0 { omissions.insert(.blur) }
                if unit.motion != .none { omissions.insert(.motionBlur) }
                if !unit.transform.isAffine { omissions.insert(.depth) }
            }
        case .shape, .group: break
        }
        if let look = layer.look {
            for paint in look.fills { note(paint) }
            for stroke in look.strokes {
                if case .image = stroke.paint { omissions.insert(.pictureStrokes) } else { note(stroke.paint) }
            }
        }
    }

    private func note(_ paint: ResolvedPaint) {
        switch paint {
        case .angular: omissions.insert(.angularGradients)
        case .radial(_, _, _, let aspect): if abs(aspect - 1) > 1e-6 { omissions.insert(.ovalGradients) }
        case .image(let image): if image.tiles { omissions.insert(.tiledPictures) }
        case .solid, .linear: break
        }
    }

    // MARK: Writing

    /// The whole animation as Lottie JSON.
    func write(name: String, job: ExportJob, progress: (Double) -> Void) throws -> LottieJSON {
        guard frameCount > 0 else { throw ExportError.failed("There are no frames to export.") }
        try record(job: job, progress: progress)

        var top: [Plan] = []
        if let background = project.composition.background.isTransparent ? nil : Optional(project.composition.background.color) {
            top.append(backgroundPlan(background))
        }
        top += plans(for: project.layers)

        let rate = timing.frameRate.perSecond
        var assets: [LottieJSON] = images.map { image in
            .object([("id", .string(image.id)), ("w", .number(Double(image.width))), ("h", .number(Double(image.height))),
                     ("u", .string(embedsImages ? "" : "/images/")),
                     ("p", .string(embedsImages
                         ? "data:image/\(image.fileExtension == "jpg" ? "jpeg" : "png");base64,\(image.data.base64EncodedString())"
                         : "\(image.id).\(image.fileExtension)")),
                     ("e", .number(embedsImages ? 1 : 0))])
        }
        let total = Double(max(comps.count + 1, 1))
        for (i, comp) in comps.enumerated() {
            if job.isCancelled { throw ExportError.cancelled }
            assets.append(.object([("id", .string(comp.id)), ("nm", .string(comp.name)), ("fr", .number(rate)),
                                   ("layers", .array(json(comp.plans)))]))
            progress(0.8 + 0.2 * Double(i + 1) / total)
        }
        let layers = json(top)
        progress(1)
        return .object([
            ("v", .string("5.7.0")), ("fr", .number(rate)), ("ip", .number(0)), ("op", .number(Double(frameCount))),
            ("w", .number(Double(project.composition.width))), ("h", .number(Double(project.composition.height))),
            ("nm", .string(name)), ("ddd", .number(0)), ("assets", .array(assets)), ("layers", .array(layers)),
            ("markers", .array([])),
        ])
    }

    // MARK: Plans

    /// One Lottie layer, before its frames are worked out.
    final class Plan {
        enum Kind {
            case shape([Group])
            case image(id: String)
            case precomp(id: String)
        }

        enum Matte { case none, source, alpha, alphaInverted }

        var name: String
        var kind: Kind
        var blend = 0
        var matte = Matte.none
        /// How many clips (Lottie masks) it has; each frame gives a path
        /// for each.
        var masks = 0
        let frame: (Int) -> Frame?

        init(name: String, kind: Kind, masks: Int = 0, frame: @escaping (Int) -> Frame?) {
            self.name = name
            self.kind = kind
            self.masks = masks
            self.frame = frame
        }
    }

    /// One group of a shape layer: paths and the paints drawn with them.
    struct Group {
        var ops: [PaintOp]
        var fillRule: FillRule
    }

    enum PaintOp {
        case solidFill
        case gradientFill(radial: Bool, stops: Int)
        case stroke(cap: LineCap, join: LineJoin, dashes: Int)
        case gradientStroke(radial: Bool, stops: Int, cap: LineCap, join: LineJoin, dashes: Int)
    }

    /// A plan at one frame.
    struct Frame {
        var transform: Affine
        var opacity: Double
        /// For each group, its path.
        var paths: [BezierPath] = []
        /// For each paint of each group, in order, its numbers.
        var paints: [[Double]] = []
        /// One path a clip.
        var masks: [BezierPath] = []
    }

    /// Where a layer is at a frame: as resolved, and from its own space
    /// into the composition's.
    typealias Place = (Int) -> (layer: ResolvedLayer, world: Affine)?

    private func place(_ id: UUID) -> Place {
        guard let r = recordings[id] else { return { _ in nil } }
        return { f in
            guard let s = r.at(f), let world = s.world else { return nil }
            return (s.layer, world)
        }
    }

    /// The plans for `layers`, back to front, siblings in the order they are
    /// drawn at the first frame.
    private func plans(for layers: [Layer]) -> [Plan] {
        let drawn = layers.enumerated().sorted { a, b in
            let ra = rank[a.element.id] ?? Int.max, rb = rank[b.element.id] ?? Int.max
            return ra != rb ? ra < rb : a.offset < b.offset
        }.map(\.element)
        return drawn.flatMap(plans(for:))
    }

    private func plans(for layer: Layer) -> [Plan] {
        guard !layer.isMask, let r = recordings[layer.id], r.frames.contains(where: { $0 >= 0 }) else { return [] }
        let samples = r.all
        let place = place(layer.id)
        let masked = samples.contains { $0.layer.mask != nil }
        let blend = Self.blend(layer.blendMode)
        if case .group(let group) = layer.content {
            let revealed = samples.contains { $0.layer.reveal != .none }
            let isolated = masked || revealed || blend != 0 || group.clipsContent
                || samples.contains { $0.layer.opacity < 1 - 1e-9 }
            var inside = shapePlans(name: layer.name, place: place, part: .fills)
            inside += plans(for: group.children)
            inside += shapePlans(name: layer.name, place: place, part: .strokes)
            guard isolated, !inside.isEmpty else { return inside }
            let plan = precomp(name: layer.name, plans: inside, place: place, clips: group.clipsContent,
                               revealed: revealed)
            plan.blend = blend
            return matted(plan, layer: layer.id, place: place, masked: masked)
        }
        var made: [Plan]
        switch layer.content {
        case .shape: made = shapePlans(name: layer.name, place: place, part: .all)
        case .text: made = textPlans(name: layer.name, place: place)
        case .video, .audio, .group: made = []
        }
        guard !made.isEmpty else { return [] }
        if masked || (blend != 0 && made.count > 1) {
            let plan = precomp(name: layer.name, plans: made, place: { f in place(f).map { ($0.layer, .identity) } },
                               clips: false, revealed: false)
            plan.blend = blend
            return matted(plan, layer: layer.id, place: place, masked: masked)
        }
        for plan in made where plan.matte != .source { plan.blend = blend }
        return made
    }

    /// `plan` with the mask its layer is masked by drawn above it as a matte.
    private func matted(_ plan: Plan, layer: UUID, place: @escaping Place, masked: Bool) -> [Plan] {
        guard masked, let r = recordings[layer],
              let maskID = r.all.lazy.compactMap({ $0.layer.mask?.layerID }).first,
              let maskRecording = recordings[maskID] else { return [plan] }
        let maskPlace: Place = { f in
            guard let (owner, world) = place(f), let link = owner.mask, let mask = maskRecording.at(f)?.layer,
                  let fromMask = LottieGeometry.flat(link.transform, over: mask.size) else { return nil }
            return (mask, fromMask.then(world))
        }
        let maskLayer = project.layer(withID: maskID)
        var source: [Plan]
        switch maskLayer?.content {
        case .shape: source = shapePlans(name: "\(maskLayer?.name ?? "Mask")", place: maskPlace, part: .all)
        case .text: source = textPlans(name: "\(maskLayer?.name ?? "Mask")", place: maskPlace)
        default: source = []
        }
        guard !source.isEmpty else { return [plan] }
        let matte: Plan
        if source.count == 1, source[0].matte == .none {
            matte = source[0]
        } else {
            matte = precomp(name: maskLayer?.name ?? "Mask", plans: source,
                            place: { f in maskPlace(f).map { ($0.layer, .identity) } }, clips: false, revealed: false)
        }
        matte.matte = .source
        plan.matte = .alpha
        return [plan, matte]
    }

    /// A precomp the composition's size holding `plans`, which are already
    /// in the composition's space. A Mask preset on the group moves the
    /// whole of it inside its clip; a frame that clips cuts to its outline.
    private func precomp(name: String, plans: [Plan], place: @escaping Place, clips: Bool, revealed: Bool) -> Plan {
        let id = "comp_\(comps.count)"
        comps.append((id, name, plans))
        let masks = (clips ? 1 : 0) + (revealed ? 1 : 0)
        return Plan(name: name, kind: .precomp(id: id), masks: masks) { f in
            guard let (layer, world) = place(f) else { return nil }
            var frame = Frame(transform: .identity, opacity: layer.opacity)
            if clips {
                let outline = layer.frame?.path ?? LottieGeometry.rectangle(Box(origin: .zero, size: layer.size))
                frame.masks.append(LottieGeometry.transformed(outline, by: world))
            }
            if revealed {
                let shift = Self.revealShift(layer.reveal, size: layer.size)
                if let back = world.inverted {
                    frame.transform = back.then(shift).then(world)
                    frame.masks.append(Self.revealClip(layer.reveal, size: layer.size, from: back.then(shift)))
                }
            }
            return frame
        }
    }

    /// How a Mask preset moves a layer's content inside its own box.
    private static func revealShift(_ reveal: Reveal, size: Size2) -> Affine {
        guard reveal != .none else { return .identity }
        let b = reveal.box
        let c = Vec2(size.width / 2, size.height / 2)
        return Affine.translation(Vec2(-c.x, -c.y)).then(.scale(Vec2(b.zoom, b.zoom)))
            .then(.translation(Vec2(c.x + b.dx * size.width, c.y + b.dy * size.height)))
    }

    /// A Mask preset's clip, in a plan's own space, given the way from that
    /// space into the layer's (`toLayer`). With no preset under way, a clip
    /// far bigger than anything drawn.
    private static func revealClip(_ reveal: Reveal, size: Size2, from toLayer: Affine) -> BezierPath {
        let rect: Box
        if reveal == .none {
            rect = Box(minX: -100_000, minY: -100_000, maxX: 100_000, maxY: 100_000)
        } else {
            let b = reveal.box
            rect = Box(origin: Vec2(b.x * size.width, b.y * size.height),
                       size: Size2(b.width * size.width, b.height * size.height))
        }
        guard let back = toLayer.inverted else {
            return LottieGeometry.rectangle(Box(minX: 0, minY: 0, maxX: 0, maxY: 0))
        }
        return LottieGeometry.transformed(LottieGeometry.rectangle(rect), by: back)
    }

    private func backgroundPlan(_ color: RGBA) -> Plan {
        let size = project.composition.size
        let path = LottieGeometry.rectangle(Box(origin: .zero, size: size))
        return Plan(name: "Background", kind: .shape([Group(ops: [.solidFill], fillRule: .nonZero)])) { _ in
            Frame(transform: .identity, opacity: 1, paths: [path], paints: [[color.r, color.g, color.b, color.a * 100]])
        }
    }

    // MARK: Shapes

    enum Part { case all, fills, strokes }

    /// A shape's (or a frame's own) fills and strokes as plans, bottom
    /// first: runs of plain paints share a shape layer; a picture fill is an
    /// image layer cut to the outline, and a stroke inside or outside the
    /// outline is drawn twice as wide and cut to it (or away from it), as
    /// Lottie strokes only straddle the path.
    private func shapePlans(name: String, place: @escaping Place, part: Part) -> [Plan] {
        guard let first = (0..<frameCount).lazy.compactMap({ place($0)?.layer.look }).first else { return [] }
        let revealed = (0..<frameCount).contains { place($0)?.layer.reveal ?? .none != .none }
        var out: [Plan] = []
        // A run of plain paints, grouped by the path they draw along: the
        // outline (-1), or a trimmed stroke's own path (its index).
        typealias Run = (group: Group, key: Int, values: [(ResolvedShape) -> [Double]?])
        var groups: [Run] = []
        func flush() {
            guard !groups.isEmpty else { return }
            let made = groups
            groups = []
            out.append(shapePlan(name: name, place: place, revealed: revealed, groups: made.map(\.group)) { look in
                (made.map { Self.path(of: look, key: $0.key) }, made.flatMap { g in g.values.map { $0(look) ?? [] } })
            })
        }
        func add(_ op: PaintOp, path key: Int, fillRule: FillRule, value: @escaping (ResolvedShape) -> [Double]?) {
            if key < 0, let last = groups.indices.last, groups[last].key < 0, groups[last].group.fillRule == fillRule {
                groups[last].group.ops.append(op)
                groups[last].values.append(value)
            } else {
                groups.append((Group(ops: [op], fillRule: fillRule), key, [value]))
            }
        }

        if part != .strokes {
            for (i, paint) in first.fills.enumerated() {
                if case .image(let image) = paint {
                    flush()
                    out += imagePlans(name: name, place: place, revealed: revealed, fill: i, first: image)
                    continue
                }
                let op = Self.fillOp(paint)
                add(op, path: -1, fillRule: first.fillRule) { look in
                    look.fills.indices.contains(i) ? Self.fillValues(look.fills[i], as: op) : nil
                }
            }
        }
        if part != .fills {
            for (i, stroke) in first.strokes.enumerated() {
                if case .image = stroke.paint { continue }
                let op = Self.strokeOp(stroke)
                let value: (ResolvedShape) -> [Double]? = { look in
                    look.strokes.indices.contains(i) ? Self.strokeValues(look.strokes[i], as: op, widthScale: 1) : nil
                }
                if stroke.alignment == .center || !first.isClosed {
                    add(op, path: stroke.trimmed == nil ? -1 : i, fillRule: first.fillRule, value: value)
                } else {
                    flush()
                    out += alignedStroke(name: name, place: place, revealed: revealed, stroke: i, op: op,
                                         inside: stroke.alignment == .inside, fillRule: first.fillRule)
                }
            }
        }
        flush()
        return out
    }

    /// The outline (`key` -1), or a trimmed stroke's own path.
    private static func path(of look: ResolvedShape, key: Int) -> BezierPath {
        guard key >= 0, look.strokes.indices.contains(key) else { return look.path }
        return look.strokes[key].trimmed ?? look.path
    }

    /// A shape layer drawing `groups`, each frame's paths and paint numbers
    /// coming from `content`.
    private func shapePlan(name: String, place: @escaping Place, revealed: Bool, groups: [Group],
                           extra: Affine = .identity,
                           content: @escaping (ResolvedShape) -> (paths: [BezierPath], paints: [[Double]])) -> Plan {
        Plan(name: name, kind: .shape(groups), masks: revealed ? 1 : 0) { f in
            guard let (layer, world) = place(f), let look = layer.look else { return nil }
            let shift = Self.revealShift(layer.reveal, size: layer.size)
            let made = content(look)
            var frame = Frame(transform: extra.then(shift).then(world), opacity: layer.opacity,
                              paths: made.paths, paints: made.paints)
            if revealed { frame.masks = [Self.revealClip(layer.reveal, size: layer.size, from: extra.then(shift))] }
            return frame
        }
    }

    /// The outline filled opaque, for cutting something else to it.
    private func outlineMatte(name: String, place: @escaping Place, fillRule: FillRule) -> Plan {
        let plan = shapePlan(name: "\(name) outline", place: place, revealed: false,
                             groups: [Group(ops: [.solidFill], fillRule: fillRule)]) { look in
            ([look.path], [[1, 1, 1, 100]])
        }
        plan.matte = .source
        return plan
    }

    private func alignedStroke(name: String, place: @escaping Place, revealed: Bool, stroke i: Int, op: PaintOp,
                               inside: Bool, fillRule: FillRule) -> [Plan] {
        let plan = shapePlan(name: "\(name) stroke", place: place, revealed: revealed,
                             groups: [Group(ops: [op], fillRule: fillRule)]) { look in
            guard look.strokes.indices.contains(i) else { return ([look.path], [[]]) }
            let stroke = look.strokes[i]
            return ([stroke.trimmed ?? look.path], [Self.strokeValues(stroke, as: op, widthScale: 2)])
        }
        plan.matte = inside ? .alpha : .alphaInverted
        return [plan, outlineMatte(name: name, place: place, fillRule: fillRule)]
    }

    private func imagePlans(name: String, place: @escaping Place, revealed: Bool, fill i: Int, first: ResolvedImage) -> [Plan] {
        guard let asset = imageAsset(first.mediaID) else { return [] }
        let size = Size2(Double(asset.width), Double(asset.height))
        let plan = Plan(name: "\(name) picture", kind: .image(id: asset.id), masks: revealed ? 1 : 0) { f in
            guard let (layer, world) = place(f), let look = layer.look else { return nil }
            var image = first
            var shown = 1.0
            if look.fills.indices.contains(i), case .image(let now) = look.fills[i] { image = now } else { shown = 0 }
            let placement = Self.placement(of: image, size: size)
            let shift = Self.revealShift(layer.reveal, size: layer.size)
            var frame = Frame(transform: placement.then(shift).then(world), opacity: layer.opacity * image.opacity * shown)
            if revealed { frame.masks = [Self.revealClip(layer.reveal, size: layer.size, from: placement.then(shift))] }
            return frame
        }
        plan.matte = .alpha
        return [plan, outlineMatte(name: name, place: place, fillRule: .nonZero)]
    }

    /// From a picture's pixels into the layer's space: its box, after its
    /// quarter turns clockwise.
    static func placement(of image: ResolvedImage, size: Size2) -> Affine {
        let f = image.frame
        let w = max(size.width, 1), h = max(size.height, 1)
        switch ((image.turns % 4) + 4) % 4 {
        case 1: return Affine(a: 0, b: f.height / w, c: -f.width / h, d: 0, tx: f.minX + f.width, ty: f.minY)
        case 2: return Affine(a: -f.width / w, b: 0, c: 0, d: -f.height / h, tx: f.minX + f.width, ty: f.minY + f.height)
        case 3: return Affine(a: 0, b: -f.height / w, c: f.width / h, d: 0, tx: f.minX, ty: f.minY + f.height)
        default: return Affine(a: f.width / w, b: 0, c: 0, d: f.height / h, tx: f.minX, ty: f.minY)
        }
    }

    private func imageAsset(_ id: UUID) -> LottieImage? {
        if let i = imageIDs[id] { return images[i] }
        guard let image = library.image(id) else { return nil }
        let isJPEG = ["jpg", "jpeg"].contains(media[id]?.pathExtension.lowercased() ?? "")
            && [.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let data = NSMutableData()
        let type = isJPEG ? UTType.jpeg : UTType.png
        guard let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image,
                                   isJPEG ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        let made = LottieImage(id: "image_\(images.count)", width: image.width, height: image.height,
                               data: data as Data, fileExtension: isJPEG ? "jpg" : "png")
        imageIDs[id] = images.count
        images.append(made)
        return made
    }

    // MARK: Paints

    private static func fillOp(_ paint: ResolvedPaint) -> PaintOp {
        switch paint {
        case .linear(let stops, _, _): .gradientFill(radial: false, stops: max(stops.count, 1))
        case .radial(let stops, _, _, _): .gradientFill(radial: true, stops: max(stops.count, 1))
        case .solid, .angular, .image: .solidFill
        }
    }

    private static func strokeOp(_ stroke: ResolvedStroke) -> PaintOp {
        let dashes = dashList(stroke.dashPattern).count
        switch stroke.paint {
        case .linear(let stops, _, _):
            return .gradientStroke(radial: false, stops: max(stops.count, 1), cap: stroke.cap, join: stroke.join, dashes: dashes)
        case .radial(let stops, _, _, _):
            return .gradientStroke(radial: true, stops: max(stops.count, 1), cap: stroke.cap, join: stroke.join, dashes: dashes)
        case .solid, .angular, .image:
            return .stroke(cap: stroke.cap, join: stroke.join, dashes: dashes)
        }
    }

    /// Dashes and gaps in pairs, as Lottie takes them: an odd list is
    /// repeated, as SVG and Core Graphics read it.
    private static func dashList(_ pattern: [Double]) -> [Double] {
        guard !pattern.isEmpty else { return [] }
        return pattern.count % 2 == 1 ? pattern + pattern : pattern
    }

    /// A colour for a paint Lottie cannot draw as it is: the average of an
    /// angular gradient's stops.
    private static func solidColor(_ paint: ResolvedPaint) -> RGBA {
        switch paint {
        case .solid(let c): return c
        case .linear(let stops, _, _), .radial(let stops, _, _, _), .angular(let stops, _, _):
            guard !stops.isEmpty else { return .clear }
            let n = Double(stops.count)
            return RGBA(stops.map(\.color.r).reduce(0, +) / n, stops.map(\.color.g).reduce(0, +) / n,
                        stops.map(\.color.b).reduce(0, +) / n, stops.map(\.color.a).reduce(0, +) / n)
        case .image: return .clear
        }
    }

    /// A gradient's start, end and stops, as Lottie lists them: the colour
    /// stops, then the opacity stops, held to `count` stops.
    private static func gradientValues(_ paint: ResolvedPaint, count: Int) -> [Double] {
        var stops: [GradientStop] = []
        var start = Vec2.zero, end = Vec2.zero
        switch paint {
        case .linear(let s, let a, let b): stops = s; start = a; end = b
        case .radial(let s, let c, let e, _): stops = s; start = c; end = e
        default: stops = [GradientStop(position: 0, color: solidColor(paint))]
        }
        if stops.isEmpty { stops = [GradientStop(position: 0, color: .clear)] }
        while stops.count < count { stops.append(stops[stops.count - 1]) }
        if stops.count > count { stops = Array(stops.prefix(count)) }
        var out = [start.x, start.y, end.x, end.y]
        for s in stops { out += [s.position, s.color.r, s.color.g, s.color.b] }
        for s in stops { out += [s.position, s.color.a] }
        return out
    }

    private static func fillValues(_ paint: ResolvedPaint, as op: PaintOp) -> [Double] {
        switch op {
        case .gradientFill(_, let count): return gradientValues(paint, count: count)
        default:
            let c = solidColor(paint)
            return [c.r, c.g, c.b, c.a * 100]
        }
    }

    private static func strokeValues(_ stroke: ResolvedStroke, as op: PaintOp, widthScale: Double) -> [Double] {
        var dashes = dashList(stroke.dashPattern)
        let count: Int
        var out: [Double]
        switch op {
        case .gradientStroke(_, let stops, _, _, let n):
            count = n
            out = gradientValues(stroke.paint, count: stops) + [stroke.width * widthScale]
        case .stroke(_, _, let n):
            count = n
            let c = solidColor(stroke.paint)
            out = [c.r, c.g, c.b, c.a * 100, stroke.width * widthScale]
        default:
            return []
        }
        while dashes.count < count { dashes.append(dashes.last ?? 0) }
        out += dashes.prefix(count)
        out.append(count > 0 ? stroke.dashOffset : 0)
        return out
    }

    // MARK: Text

    private func glyphs(_ key: LottieText.Key) -> (path: BezierPath, size: Size2) {
        if let made = outlines[key] { return made }
        let made = LottieText.outlines(key)
        outlines[key] = made
        return made
    }

    /// One part of a text at one frame: which characters, set how, and
    /// from the text's space to where it is drawn.
    private struct Piece {
        var key: LottieText.Key
        /// From the piece's glyph space into the layer's, before a Mask
        /// preset on the layer moves it.
        var transform: Affine
        var opacity: Double
        /// A clip of its own, as a letter, word or line's Mask preset draws.
        var clip: (reveal: Reveal, size: Size2, toUnit: Affine)?
    }

    /// The parts a text is drawn as at one frame: each letter, word or line
    /// a text preset moves, or the whole text and, during a swap, the one
    /// leaving.
    private func pieces(_ t: ResolvedText, size: Size2) -> [Piece] {
        let width = t.sizing == .fixedWidth ? size.width : nil
        let style = t.style
        if !t.units.isEmpty {
            return t.units.map { unit in
                let key = LottieText.Key(text: t.text, style: style, width: width, range: unit.range)
                let toUnit = Affine.translation(Vec2(-unit.box.minX, -unit.box.minY))
                let shift = Self.revealShift(unit.reveal, size: Size2(unit.box.width, unit.box.height))
                let placed = LottieGeometry.flat(unit.transform, over: Size2(unit.box.width, unit.box.height)) ?? .scale(.zero)
                return Piece(key: key, transform: toUnit.then(shift).then(placed), opacity: unit.opacity,
                             clip: unit.reveal == .none ? nil : (unit.reveal, Size2(unit.box.width, unit.box.height), toUnit.then(shift)))
            }
        }
        var out: [Piece] = []
        let texts: [(String, Bool)] = [t.swap.map { ($0.previous, true) }, (t.text, false)].compactMap { $0 }
        for (string, leaving) in texts {
            let progress: Double, transition: TextTransition
            if leaving {
                guard let swap = t.swap, swap.outProgress < 1 else { continue }
                progress = swap.outProgress
                transition = swap.transitionOut
            } else {
                if let swap = t.swap, swap.inProgress <= 0 { continue }
                progress = t.swap?.inProgress ?? 1
                transition = t.swap?.transitionIn ?? .none
            }
            let key = LottieText.Key(text: string, style: style, width: width, range: nil)
            let box = glyphs(key).size
            let x: Double
            switch t.alignment {
            case .left, .justified: x = 0
            case .center: x = (size.width - box.width) / 2
            case .right: x = size.width - box.width
            }
            let shown = leaving ? 1 - progress : progress
            var effect = Affine.identity
            var opacity = 1.0
            switch transition {
            case .none: break
            case .fade: opacity = shown
            case .slide:
                opacity = shown
                effect = .translation(Vec2(0, leaving ? -t.fontSize * progress : t.fontSize * (1 - progress)))
            case .scale:
                opacity = shown
                let s = 0.6 + 0.4 * shown
                let c = Vec2(x + box.width / 2, box.height / 2)
                effect = Affine.translation(Vec2(-c.x, -c.y)).then(.scale(Vec2(s, s))).then(.translation(c))
            }
            out.append(Piece(key: key, transform: Affine.translation(Vec2(x, 0)).then(effect), opacity: opacity, clip: nil))
        }
        return out
    }

    private func textPlans(name: String, place: @escaping Place) -> [Plan] {
        // Every part the text is ever drawn as, in the order first seen.
        var keys: [LottieText.Key] = []
        var seen = Set<LottieText.Key>()
        var first: ResolvedText?
        var revealed = false
        var clipped = Set<LottieText.Key>()
        // Each frame's parts, worked out once rather than once a part.
        var byFrame = [[LottieText.Key: Piece]](repeating: [:], count: frameCount)
        var last: (text: ResolvedText, size: Size2, pieces: [Piece])?
        for f in 0..<frameCount {
            guard let (layer, _) = place(f), case .text(let t) = layer.content else { continue }
            if first == nil { first = t }
            if layer.reveal != .none { revealed = true }
            let made: [Piece]
            if let last, last.text == t, last.size == layer.size { made = last.pieces } else {
                made = pieces(t, size: layer.size)
                last = (t, layer.size, made)
            }
            for piece in made {
                byFrame[f][piece.key] = piece
                if seen.insert(piece.key).inserted { keys.append(piece.key) }
                if piece.clip != nil { clipped.insert(piece.key) }
            }
        }
        guard let first else { return [] }
        var out: [Plan] = []
        for key in keys {
            let path = glyphs(key).path
            guard !path.subpaths.isEmpty else { continue }
            let clips = (clipped.contains(key) ? 1 : 0) + (revealed ? 1 : 0)
            // The piece at a frame, and where it goes.
            let at: (Int) -> (layer: ResolvedLayer, text: ResolvedText, piece: Piece, world: Affine)? = { [byFrame] f in
                guard let (layer, world) = place(f), case .text(let t) = layer.content,
                      let piece = byFrame[f][key] else { return nil }
                return (layer, t, piece, world)
            }
            func frame(_ f: Int, paints: (ResolvedText) -> [Double]?) -> Frame? {
                guard let (layer, t, piece, world) = at(f) else { return nil }
                let shift = Self.revealShift(layer.reveal, size: layer.size)
                var frame = Frame(transform: piece.transform.then(shift).then(world), opacity: layer.opacity * piece.opacity,
                                  paths: [path], paints: paints(t).map { [$0] } ?? [])
                if clipped.contains(key) {
                    frame.masks.append(piece.clip.map { Self.revealClip($0.reveal, size: $0.size, from: $0.toUnit) }
                        ?? Self.revealClip(.none, size: layer.size, from: .identity))
                }
                if revealed { frame.masks.append(Self.revealClip(layer.reveal, size: layer.size, from: piece.transform.then(shift))) }
                return frame
            }
            let fill = Plan(name: name, kind: .shape([Group(ops: [.solidFill], fillRule: .nonZero)]), masks: clips) { f in
                frame(f) { t in t.showsFill ? [t.color.r, t.color.g, t.color.b, t.color.a * 100] : [0, 0, 0, 0] }
            }
            guard let stroke = first.stroke else {
                out.append(fill)
                continue
            }
            let op = PaintOp.stroke(cap: .butt, join: stroke.join, dashes: 0)
            let scale = stroke.alignment == .center ? 1.0 : 2.0
            let strokePlan = Plan(name: "\(name) stroke", kind: .shape([Group(ops: [op], fillRule: .nonZero)]), masks: clips) { f in
                frame(f) { t in
                    let s = t.stroke ?? stroke
                    return [s.color.r, s.color.g, s.color.b, (t.stroke == nil ? 0 : s.color.a) * 100, s.width * scale, 0]
                }
            }
            switch stroke.alignment {
            case .center:
                out += [fill, strokePlan]
            case .inside, .outside:
                let matte = Plan(name: "\(name) outline", kind: .shape([Group(ops: [.solidFill], fillRule: .nonZero)])) { f in
                    var made = frame(f) { _ in [1, 1, 1, 100] }
                    made?.masks = []
                    return made
                }
                matte.matte = .source
                strokePlan.matte = stroke.alignment == .inside ? .alpha : .alphaInverted
                out += stroke.alignment == .inside ? [fill, strokePlan, matte] : [strokePlan, matte, fill]
            }
        }
        return out
    }

    // MARK: JSON

    /// The plans as a Lottie layer list: front first, as Lottie draws them,
    /// each matte straight above the layer it cuts.
    private func json(_ plans: [Plan]) -> [LottieJSON] {
        var out: [LottieJSON] = []
        var index = 1
        for plan in plans.reversed() {
            if let made = json(plan, index: index) {
                out.append(made)
                index += 1
            }
        }
        return out
    }

    private func json(_ plan: Plan, index: Int) -> LottieJSON? {
        let n = frameCount
        var frames = (0..<n).map(plan.frame)
        guard let firstPresent = frames.firstIndex(where: { $0 != nil }),
              let lastPresent = frames.lastIndex(where: { $0 != nil }) else { return nil }
        // Where it is not drawn it is see-through, and otherwise as at the
        // nearest frame where it is.
        var opacities = frames.map { ($0?.opacity ?? 0) * 100 }
        var last: Frame? = frames[firstPresent]
        for f in 0..<n {
            if let made = frames[f] { last = made } else { frames[f] = last; opacities[f] = 0 }
        }
        let filled = frames.map { $0! }

        var transforms: [LottieTransform] = []
        transforms.reserveCapacity(n)
        for frame in filled {
            transforms.append(LottieTransform(frame.transform, previousRotation: transforms.last?.rotation))
        }
        let ks: LottieJSON = .object([
            ("o", Series(values: opacities.map { [$0] }, tolerance: 0.05).property(.scalar)),
            ("r", Series(values: transforms.map { [$0.rotation] }, tolerance: 0.005).property(.scalar)),
            ("p", Series(values: transforms.map { [$0.position.x, $0.position.y] }, tolerance: 0.005).property(.spatial)),
            ("a", .object([("a", .number(0)), ("k", .numbers([0, 0]))])),
            ("s", Series(values: transforms.map { [$0.scale.x, $0.scale.y] }, tolerance: 0.005).property(.vector)),
            ("sk", Series(values: transforms.map { [$0.skew] }, tolerance: 0.005).property(.scalar)),
            ("sa", .object([("a", .number(0)), ("k", .number(0))])),
        ])

        var pairs: [(String, LottieJSON)] = [("ddd", .number(0)), ("ind", .number(Double(index)))]
        switch plan.kind {
        case .shape: pairs.append(("ty", .number(4)))
        case .image(let id): pairs += [("ty", .number(2)), ("refId", .string(id))]
        case .precomp(let id):
            pairs += [("ty", .number(0)), ("refId", .string(id)),
                      ("w", .number(Double(project.composition.width))), ("h", .number(Double(project.composition.height)))]
        }
        pairs += [("nm", .string(plan.name)), ("sr", .number(1)), ("ks", ks), ("ao", .number(0))]
        switch plan.matte {
        case .none: break
        case .source: pairs.append(("td", .number(1)))
        case .alpha: pairs.append(("tt", .number(1)))
        case .alphaInverted: pairs.append(("tt", .number(2)))
        }
        if plan.masks > 0 {
            pairs.append(("hasMask", .bool(true)))
            pairs.append(("masksProperties", .array((0..<plan.masks).map { m in
                let paths = filled.map { $0.masks.indices.contains(m) ? $0.masks[m].subpaths.first : nil }
                return .object([("inv", .bool(false)), ("mode", .string(m == 0 ? "a" : "i")),
                                ("pt", Self.pathProperty(paths)),
                                ("o", .object([("a", .number(0)), ("k", .number(100))])),
                                ("x", .object([("a", .number(0)), ("k", .number(0))])), ("nm", .string("Clip \(m + 1)"))])
            })))
        }
        if case .shape(let groups) = plan.kind {
            pairs.append(("shapes", .array(shapes(groups, frames: filled))))
        }
        pairs += [("ip", .number(Double(firstPresent))), ("op", .number(Double(lastPresent + 1))),
                  ("st", .number(0)), ("bm", .number(Double(plan.blend)))]
        return .object(pairs)
    }

    /// A path that changes, or does not, as a Lottie property. Paths that
    /// stay the same are compared before any of their numbers are listed:
    /// most never change, and listing a big one for every frame is costly.
    private static func pathProperty(_ paths: [Subpath?]) -> LottieJSON {
        if let first = paths.first, paths.allSatisfy({ $0 == first }) {
            return .object([("a", .number(0)),
                            ("k", LottieGeometry.lottiePath(LottieGeometry.numbers(first).values, closed: first?.isClosed ?? false))])
        }
        let (uniform, closed) = LottieGeometry.uniform(paths)
        let series = Series(values: uniform.map { LottieGeometry.numbers($0).values }, tolerance: 0.005)
        return series.property(.shape(make: { LottieGeometry.lottiePath($0, closed: closed) }))
    }

    private func shapes(_ groups: [Group], frames: [Frame]) -> [LottieJSON] {
        var made: [LottieJSON] = []
        var paintIndex = 0
        for (g, group) in groups.enumerated() {
            let paths = frames.map { $0.paths.indices.contains(g) ? $0.paths[g] : BezierPath() }
            let subpaths = paths.map(\.subpaths.count).max() ?? 0
            var items: [LottieJSON] = (0..<subpaths).map { k in
                let property = Self.pathProperty(paths.map { $0.subpaths.indices.contains(k) ? $0.subpaths[k] : nil })
                return .object([("ty", .string("sh")), ("nm", .string("Path \(k + 1)")), ("ks", property)])
            }
            var paints: [LottieJSON] = []
            for op in group.ops {
                let i = paintIndex
                paintIndex += 1
                var values = frames.map { $0.paints.indices.contains(i) ? $0.paints[i] : [] }
                // A stroke along nothing is a dot with round caps; Twine
                // draws nothing, so it gets no width there.
                let width: Int?
                switch op {
                case .stroke: width = 4
                case .gradientStroke(_, let stops, _, _, _): width = 4 + stops * 6
                case .solidFill, .gradientFill: width = nil
                }
                if let width {
                    for f in values.indices where values[f].count > width
                        && paths[f].subpaths.allSatisfy({ $0.points.isEmpty }) { values[f][width] = 0 }
                }
                paints.append(paint(op, values: values, fillRule: group.fillRule))
            }
            // Lottie draws a group's items front first.
            items += paints.reversed()
            items.append(.object([
                ("ty", .string("tr")),
                ("p", .object([("a", .number(0)), ("k", .numbers([0, 0]))])),
                ("a", .object([("a", .number(0)), ("k", .numbers([0, 0]))])),
                ("s", .object([("a", .number(0)), ("k", .numbers([100, 100]))])),
                ("r", .object([("a", .number(0)), ("k", .number(0))])),
                ("o", .object([("a", .number(0)), ("k", .number(100))])),
                ("sk", .object([("a", .number(0)), ("k", .number(0))])),
                ("sa", .object([("a", .number(0)), ("k", .number(0))])),
            ]))
            made.append(.object([("ty", .string("gr")), ("nm", .string("Group \(g + 1)")), ("it", .array(items))]))
        }
        return made.reversed()
    }

    /// Part of each frame's paint numbers as a series, any frame missing
    /// them taking the nearest one's.
    private static func slice(_ values: [[Double]], _ range: Range<Int>, tolerance: Double) -> Series {
        var out: [[Double]] = []
        out.reserveCapacity(values.count)
        let fallback = values.first { $0.count >= range.upperBound }.map { Array($0[range]) }
            ?? Array(repeating: 0, count: range.count)
        var last = fallback
        for v in values {
            if v.count >= range.upperBound { last = Array(v[range]) }
            out.append(last)
        }
        return Series(values: out, tolerance: tolerance)
    }

    private func paint(_ op: PaintOp, values: [[Double]], fillRule: FillRule) -> LottieJSON {
        let rule: LottieJSON = .number(fillRule == .evenOdd ? 2 : 1)
        func gradient(_ stops: Int, from start: Int) -> [(String, LottieJSON)] {
            let colours = Self.slice(values, (start + 4)..<(start + 4 + stops * 6), tolerance: 0.001)
            return [
                ("s", Self.slice(values, start..<(start + 2), tolerance: 0.005).property(.vector)),
                ("e", Self.slice(values, (start + 2)..<(start + 4), tolerance: 0.005).property(.vector)),
                ("g", .object([("p", .number(Double(stops))), ("k", colours.property(.vector))])),
            ]
        }
        func strokeStyle(cap: LineCap, join: LineJoin, dashes: Int, widthAt w: Int) -> [(String, LottieJSON)] {
            var out: [(String, LottieJSON)] = [
                ("w", Self.slice(values, w..<(w + 1), tolerance: 0.005).property(.scalar)),
                ("lc", .number(cap == .round ? 2 : cap == .square ? 3 : 1)),
                ("lj", .number(join == .round ? 2 : join == .bevel ? 3 : 1)),
                ("ml", .number(4)),
            ]
            if dashes > 0 {
                var list: [LottieJSON] = (0..<dashes).map { k in
                    .object([("n", .string(k % 2 == 0 ? "d" : "g")), ("nm", .string(k % 2 == 0 ? "dash" : "gap")),
                             ("v", Self.slice(values, (w + 1 + k)..<(w + 2 + k), tolerance: 0.005).property(.scalar))])
                }
                list.append(.object([("n", .string("o")), ("nm", .string("offset")),
                                     ("v", Self.slice(values, (w + 1 + dashes)..<(w + 2 + dashes), tolerance: 0.005).property(.scalar))]))
                out.append(("d", .array(list)))
            }
            return out
        }
        switch op {
        case .solidFill:
            return .object([("ty", .string("fl")), ("nm", .string("Fill")),
                            ("c", Self.colour(values)), ("o", Self.slice(values, 3..<4, tolerance: 0.05).property(.scalar)),
                            ("r", rule)])
        case .gradientFill(let radial, let stops):
            return .object([("ty", .string("gf")), ("nm", .string("Gradient fill")),
                            ("o", .object([("a", .number(0)), ("k", .number(100))])), ("r", rule),
                            ("t", .number(radial ? 2 : 1))] + gradient(stops, from: 0)
                + (radial ? [("h", .object([("a", .number(0)), ("k", .number(0))])),
                             ("a", .object([("a", .number(0)), ("k", .number(0))]))] : []))
        case .stroke(let cap, let join, let dashes):
            return .object([("ty", .string("st")), ("nm", .string("Stroke")),
                            ("c", Self.colour(values)), ("o", Self.slice(values, 3..<4, tolerance: 0.05).property(.scalar))]
                + strokeStyle(cap: cap, join: join, dashes: dashes, widthAt: 4))
        case .gradientStroke(let radial, let stops, let cap, let join, let dashes):
            return .object([("ty", .string("gs")), ("nm", .string("Gradient stroke")),
                            ("o", .object([("a", .number(0)), ("k", .number(100))])),
                            ("t", .number(radial ? 2 : 1))] + gradient(stops, from: 0)
                + (radial ? [("h", .object([("a", .number(0)), ("k", .number(0))])),
                             ("a", .object([("a", .number(0)), ("k", .number(0))]))] : [])
                + strokeStyle(cap: cap, join: join, dashes: dashes, widthAt: 4 + stops * 6))
        }
    }

    /// A colour property: red, green and blue, with alpha 1, the paint's own
    /// opacity going into its opacity property.
    private static func colour(_ values: [[Double]]) -> LottieJSON {
        let rgb = slice(values, 0..<3, tolerance: 0.001)
        var withAlpha = rgb
        withAlpha.values = rgb.values.map { $0 + [1] }
        return withAlpha.property(.vector)
    }

    /// Lottie's number for a blend mode. It has no Linear Burn; Multiply is
    /// the nearest.
    static func blend(_ mode: BlendMode) -> Int {
        switch mode {
        case .normal: 0
        case .multiply, .linearBurn: 1
        case .screen: 2
        case .overlay: 3
        case .darken: 4
        case .lighten: 5
        case .colorDodge: 6
        case .colorBurn: 7
        case .hardLight: 8
        case .softLight: 9
        case .difference: 10
        case .exclusion: 11
        case .hue: 12
        case .saturation: 13
        case .color: 14
        case .luminosity: 15
        case .linearDodge: 16
        }
    }
}
