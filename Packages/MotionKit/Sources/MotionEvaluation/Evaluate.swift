import Foundation
import MotionModel

/// Works out what the composition looks like at `time`, with every action
/// applied.
///
/// A pure function: the same project and the same time always give the same
/// scene, and any time works, including between frames. The canvas, export,
/// thumbnails and (later) motion blur all call this and nothing else.
///
/// A layer is in the scene when it is switched on and no action has hidden
/// it. If any layer is soloed, only soloed layers show, with everything inside
/// a soloed group and the groups that contain a soloed layer. Audio layers draw
/// nothing and are left out. Layers used as another layer's mask go in the
/// scene's `masks` instead, whatever is soloed, so a mask keeps working.
public func evaluate(_ project: Project, at time: Double) -> ResolvedScene {
    scene(of: project, at: time, tracks: ActionTracks(project.actions))
}

/// The composition as designed, with no actions applied: what Design mode
/// shows.
public func evaluateDesign(_ project: Project) -> ResolvedScene {
    scene(of: project, at: 0, tracks: ActionTracks([]))
}

private func scene(of project: Project, at time: Double, tracks: ActionTracks) -> ResolvedScene {
    let all = project.allLayers
    let soloing = all.contains { $0.isSoloed }
    // A layer used as another's mask stops drawing on its own, and draws
    // only through the layers it masks.
    let maskSources = project.maskSourceIDs
    let pictures = project.pictureSizes
    var out: [ResolvedLayer] = []

    func hasSoloedDescendant(_ layer: Layer) -> Bool {
        layer.children.contains { $0.isSoloed || hasSoloedDescendant($0) }
    }

    func walk(_ layers: [Layer], parent: UUID?, soloedAbove: Bool) {
        for layer in layers {
            guard layer.isVisible, !maskSources.contains(layer.id) else { continue }
            let soloed = soloedAbove || layer.isSoloed
            if soloing && !soloed && !(layer.isGroup && hasSoloedDescendant(layer)) { continue }
            let state = tracks.state(of: layer, at: time)
            // Hidden by an action: the layer and everything inside it.
            guard state.isShown else { continue }
            guard let resolved = resolve(layer, state: state, parent: parent, pictures: pictures) else { continue }
            out.append(resolved)
            if layer.isGroup { walk(layer.children, parent: layer.id, soloedAbove: soloed) }
        }
    }
    walk(project.layers, parent: nil, soloedAbove: false)

    if !maskSources.isEmpty {
        var world = WorldTransforms(project: project, tracks: tracks, time: time, pictures: pictures, known: out)
        var masks: [ResolvedLayer] = []
        for id in maskSources {
            guard let layer = world.resolved(id) else { continue }
            var source = layer
            // A mask draws alone; its own mask is not followed.
            source.mask = nil
            masks.append(source)
        }
        let shown = Set(masks.map(\.id))
        for i in out.indices {
            guard let reference = project.layer(withID: out[i].id)?.mask else { continue }
            if shown.contains(reference.layerID), let from = world.transform(of: reference.layerID),
               let into = world.transform(of: out[i].id)?.inverted {
                out[i].mask = ResolvedMask(layerID: reference.layerID, isInverted: reference.isInverted,
                                           transform: from.then(into))
            } else {
                out[i].mask = nil
            }
        }
        // In drawing order, so the scene is the same whatever order the set
        // gives.
        let order = Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.id, $0) })
        masks.sort { order[$0.id, default: 0] < order[$1.id, default: 0] }
        let background = project.composition.background
        return ResolvedScene(time: time, size: project.composition.size,
                             background: background.isTransparent ? nil : background.color,
                             layers: out, masks: masks)
    }

    let background = project.composition.background
    return ResolvedScene(time: time, size: project.composition.size,
                         background: background.isTransparent ? nil : background.color,
                         layers: out)
}

/// Layers resolved on demand, with the transform from each one's space into
/// the composition's, for placing a mask over the layer it masks. Starts
/// from the layers already in the scene, and resolves others (a mask, the
/// groups a mask sits in) as they are asked for.
private struct WorldTransforms {
    let project: Project
    let tracks: ActionTracks
    let time: Double
    let pictures: [UUID: Size2]
    private var cache: [UUID: ResolvedLayer?] = [:]

    init(project: Project, tracks: ActionTracks, time: Double, pictures: [UUID: Size2], known: [ResolvedLayer]) {
        self.project = project
        self.tracks = tracks
        self.time = time
        self.pictures = pictures
        for layer in known { cache[layer.id] = layer }
    }

    /// The layer as it stands at `time`, or nil if it, or a group it sits
    /// in, is switched off or hidden.
    mutating func resolved(_ id: UUID) -> ResolvedLayer? {
        if let known = cache[id] { return known }
        var result: ResolvedLayer?
        let parent = project.location(of: id)?.parentID
        if let layer = project.layer(withID: id), layer.isVisible, parent.map({ resolved($0) != nil }) ?? true {
            let state = tracks.state(of: layer, at: time)
            if state.isShown { result = resolve(layer, state: state, parent: parent, pictures: pictures) }
        }
        cache[id] = result
        return result
    }

    mutating func transform(of id: UUID) -> Affine? {
        guard let layer = resolved(id) else { return nil }
        guard let parent = layer.parentID else { return layer.transform }
        return transform(of: parent).map { layer.transform.then($0) }
    }
}

private func resolve(_ layer: Layer, state: LayerState, parent: UUID?, pictures: [UUID: Size2]) -> ResolvedLayer? {
    var size = state.size
    let content: ResolvedContent
    var clips = false
    // A text box is as big as its words, so it is measured here, and grows
    // from its anchor the way its alignment reads.
    var textAnchor: Vec2?

    switch layer.content {
    case .shape(let shape):
        content = .shape(resolve(shape, size: size, state: state, pictures: pictures))
    case .text(let text):
        let shown = state.text ?? ShownText(text: text.text)
        var color = text.color
        switch state.fill {
        case .solid(let c): color = c
        case .linearGradient(let g), .radialGradient(let g): color = g.stops.first?.color ?? color
        case .image, nil: break
        }
        let resolved = ResolvedText(text: shown.text, swap: shown.swap, fontFamily: text.fontFamily,
                                    fontWeight: text.fontWeight, fontSize: text.fontSize, color: color,
                                    alignment: text.alignment, letterSpacing: state.letterSpacing ?? text.letterSpacing,
                                    lineHeight: state.lineHeight ?? text.lineHeight, sizing: text.sizing,
                                    tabularDigits: shown.isCounting)
        let width = text.sizing == .fixedWidth ? state.size.width : nil
        size = TextLayout.size(of: shown.visible, style: resolved.style, width: width)
        textAnchor = TextLayout.anchor(layer.transform.anchor, from: layer.size, to: size, alignment: text.alignment)
        content = .text(resolved)
    case .video(let video):
        content = .video(mediaID: video.mediaID, sourceTime: state.sourceTime ?? 0, fit: video.fit)
    case .audio:
        return nil
    case .group(let group):
        content = .group
        clips = group.clipsContent
    }

    // One shadow per layer is what Core Animation draws. Figma allows
    // several; the first one switched on wins until a renderer can do more,
    // and that is the one the Shadow action drives. The same goes for the
    // background blur. Layer blurs add up, the first carrying its action.
    var shadow: ResolvedShadow?
    let s = state.shadow
    if s.opacity > 0 && s.color.a > 0 {
        shadow = ResolvedShadow(color: s.color, offset: s.offset, blur: max(s.blur, 0),
                                opacity: min(max(s.opacity, 0), 1), spread: s.spread)
    }
    var blur = max(state.layerBlur, 0)
    let blurs = layer.effects.filter(\.isEnabled).compactMap { effect -> Double? in
        if case .layerBlur(let b) = effect.kind { return b.radius }
        return nil
    }
    blur += blurs.dropFirst().reduce(0) { $0 + max($1, 0) }
    var backgroundBlur: BackgroundBlur?
    if case .shape = layer.content, state.backgroundBlur.radius > 0, state.backgroundBlur.blend > 0 {
        backgroundBlur = state.backgroundBlur
    }

    // A resized layer grows around its anchor: the anchor keeps its place as
    // a fraction of the box, and the position keeps the anchor where it was.
    let designSize = layer.size
    let anchor = textAnchor ?? Vec2(designSize.width != 0 ? layer.transform.anchor.x * size.width / designSize.width : layer.transform.anchor.x,
                      designSize.height != 0 ? layer.transform.anchor.y * size.height / designSize.height : layer.transform.anchor.y)

    return ResolvedLayer(id: layer.id, parentID: parent, size: size,
                         position: state.position, anchor: anchor,
                         scale: state.scale, rotation: state.rotation,
                         opacity: min(max(state.opacity, 0), 1),
                         content: content, shadow: shadow, blur: blur, backgroundBlur: backgroundBlur,
                         clipsContent: clips,
                         // Filled in once every layer is resolved, since a
                         // mask can sit anywhere in the tree.
                         mask: nil)
}

/// The shape with its actions applied: the first fill's paint, the first
/// stroke's width, paint and trim, a rectangle's corners, and a pen path's
/// points. A pen path fills the layer's box as every other shape does: its
/// designed points' bounds are stretched onto the box, and a Path action's
/// points go the same way, so resizing stretches either.
private func resolve(_ shape: ShapeContent, size: Size2, state: LayerState, pictures: [UUID: Size2]) -> ResolvedShape {
    var shape = shape
    var designBounds: Box?
    if case .path(let p) = shape.geometry { designBounds = p.bounds }
    if let fill = state.fill, !shape.fills.isEmpty { shape.fills[0].paint = fill }
    if !shape.strokes.isEmpty {
        if let look = state.stroke {
            shape.strokes[0].width = look.width
            shape.strokes[0].paint = look.paint
        }
        if let trim = state.trim {
            shape.strokes[0].trimStart = trim.start
            shape.strokes[0].trimEnd = trim.end
        }
    }
    if let radii = state.cornerRadii, case .rectangle = shape.geometry { shape.geometry = .rectangle(cornerRadii: radii) }
    if let arc = state.arc, case .ellipse = shape.geometry { shape.geometry = .ellipse(arc: arc) }
    if let star = state.star, case .star = shape.geometry {
        shape.geometry = .star(points: star.points, innerRadius: star.innerRadius, cornerRadius: star.cornerRadius)
    }
    if let points = state.path, case .path = shape.geometry { shape.geometry = .path(points) }

    let path: BezierPath
    if case .path(let p) = shape.geometry {
        path = p.fitted(from: designBounds, to: size)
    } else {
        path = shape.geometry.bezierPath(size: size)
    }
    let closed = shape.geometry.isClosed

    let fills = shape.fills.filter(\.isEnabled).map { resolve($0.paint, size: size, pictures: pictures) }
    // A picture can only fill; a stroke with one is left for an importer to
    // turn into a picture of its own.
    let strokes = shape.strokes.filter { $0.isEnabled && !$0.paint.isImage }.map { stroke in
        ResolvedStroke(paint: resolve(stroke.paint, size: size, pictures: pictures),
                       width: max(stroke.width, 0),
                       alignment: closed ? stroke.alignment : .center,
                       cap: stroke.cap, join: stroke.join,
                       dashPattern: stroke.dashPattern.filter { $0 > 0 }, dashOffset: stroke.dashOffset,
                       trimStart: min(max(stroke.trimStart, 0), 1),
                       trimEnd: min(max(stroke.trimEnd, 0), 1))
    }
    return ResolvedShape(path: path, isClosed: closed, fills: fills, strokes: strokes)
}

private func resolve(_ paint: Paint, size: Size2, pictures: [UUID: Size2]) -> ResolvedPaint {
    func px(_ unit: Vec2) -> Vec2 { Vec2(unit.x * size.width, unit.y * size.height) }
    switch paint {
    case .solid(let color):
        return .solid(color)
    case .linearGradient(let g):
        return .linear(stops: g.stops.sorted { $0.position < $1.position },
                       start: px(g.start), end: px(g.end))
    case .radialGradient(let g):
        let center = px(g.start), edge = px(g.end)
        return .radial(stops: g.stops.sorted { $0.position < $1.position },
                       center: center, radius: hypot(edge.x - center.x, edge.y - center.y))
    case .image(let p):
        return .image(ResolvedImage(mediaID: p.mediaID,
                                    frame: ImagePlacement.frame(of: p, box: size, picture: pictures[p.mediaID]),
                                    turns: p.turns, tiles: p.mode == .tile, opacity: min(max(p.opacity, 0), 1)))
    }
}

extension Project {
    /// Every picture's own size in pixels, by its id, for placing picture
    /// fills.
    public var pictureSizes: [UUID: Size2] {
        var sizes: [UUID: Size2] = [:]
        for asset in media where asset.kind == .image {
            if let w = asset.pixelWidth, let h = asset.pixelHeight { sizes[asset.id] = Size2(Double(w), Double(h)) }
        }
        return sizes
    }
}

extension ShapeGeometry {
    /// The shape as a bezier path filling a box of `size`, in the layer's own
    /// pixel space. A pen path is its own points, whatever the size.
    public func bezierPath(size: Size2) -> BezierPath {
        switch self {
        case .rectangle(let radii): return ShapePaths.rectangle(size, radii: radii)
        case .ellipse(let arc): return ShapePaths.ellipse(size, arc: arc)
        case .line: return ShapePaths.line(size)
        case .polygon(let sides): return ShapePaths.polygon(size, sides: sides)
        case .star(let points, let inner, let corner):
            return ShapePaths.star(size, points: points, innerRadius: inner, cornerRadius: corner)
        case .path(let p): return p.fitted(from: p.bounds, to: size)
        }
    }
}

extension BezierPath {
    /// The points carried from `box` onto a box of `size` at the origin,
    /// stretching on each axis: how a pen path fills its layer. An axis the
    /// box has no extent on is only moved. Kept as it is when it already
    /// fits, which an edited path always does.
    public func fitted(from box: Box?, to size: Size2) -> BezierPath {
        guard let box else { return self }
        let sx = box.width > 1e-9 ? size.width / box.width : 1
        let sy = box.height > 1e-9 ? size.height / box.height : 1
        let ox = box.minX, oy = box.minY
        guard abs(sx - 1) > 1e-12 || abs(sy - 1) > 1e-12 || ox != 0 || oy != 0 else { return self }
        func point(_ v: Vec2) -> Vec2 { Vec2((v.x - ox) * sx, (v.y - oy) * sy) }
        func vector(_ v: Vec2) -> Vec2 { Vec2(v.x * sx, v.y * sy) }
        return BezierPath(subpaths: subpaths.map { sub in
            Subpath(points: sub.points.map { PathPoint(point($0.position), inHandle: vector($0.inHandle), outHandle: vector($0.outHandle)) },
                    isClosed: sub.isClosed)
        })
    }

    /// The box the curves themselves fill, not their handles, as Figma
    /// measures a vector. Nil for a path with no points.
    public var bounds: Box? {
        var box: Box?
        func add(_ p: Vec2) { box = box?.including(p) ?? Box(minX: p.x, minY: p.y, maxX: p.x, maxY: p.y) }
        for sub in subpaths {
            sub.points.forEach { add($0.position) }
            guard sub.points.count > 1 else { continue }
            let count = sub.isClosed ? sub.points.count : sub.points.count - 1
            for i in 0..<count {
                let a = sub.points[i], b = sub.points[(i + 1) % sub.points.count]
                guard a.outHandle != .zero || b.inHandle != .zero else { continue }
                let p0 = a.position, c1 = a.position + a.outHandle, c2 = b.position + b.inHandle, p1 = b.position
                for t in Self.turns(p0.x, c1.x, c2.x, p1.x) + Self.turns(p0.y, c1.y, c2.y, p1.y) {
                    let q = 1 - t
                    let wa = q * q * q, wb = 3 * q * q * t, wc = 3 * q * t * t, wd = t * t * t
                    add(Vec2(wa * p0.x + wb * c1.x + wc * c2.x + wd * p1.x, wa * p0.y + wb * c1.y + wc * c2.y + wd * p1.y))
                }
            }
        }
        return box
    }

    /// Where a cubic bezier on one axis turns, strictly between its ends.
    private static func turns(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> [Double] {
        // The derivative, as qa·t² + qb·t + qc.
        let qa = 3 * (-a + 3 * b - 3 * c + d), qb = 6 * (a - 2 * b + c), qc = 3 * (b - a)
        let roots: [Double]
        if abs(qa) < 1e-12 {
            roots = abs(qb) < 1e-12 ? [] : [-qc / qb]
        } else {
            let disc = qb * qb - 4 * qa * qc
            guard disc >= 0 else { return [] }
            let r = sqrt(disc)
            roots = [(-qb + r) / (2 * qa), (-qb - r) / (2 * qa)]
        }
        return roots.filter { $0 > 0 && $0 < 1 }
    }
}
