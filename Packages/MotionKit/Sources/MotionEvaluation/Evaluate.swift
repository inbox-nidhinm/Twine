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
/// nothing and are left out, as are layers used as another layer's mask.
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
    // A layer used as another's mask stops drawing on its own. A later
    // milestone hands mask layers to the renderer separately, to draw as
    // masks only.
    let maskSources = Set(all.compactMap { $0.mask?.layerID })
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
            guard let resolved = resolve(layer, state: state, parent: parent, at: time) else { continue }
            out.append(resolved)
            if layer.isGroup { walk(layer.children, parent: layer.id, soloedAbove: soloed) }
        }
    }
    walk(project.layers, parent: nil, soloedAbove: false)

    let background = project.composition.background
    return ResolvedScene(time: time, size: project.composition.size,
                         background: background.isTransparent ? nil : background.color,
                         layers: out)
}

private func resolve(_ layer: Layer, state: LayerState, parent: UUID?, at t: Double) -> ResolvedLayer? {
    var size = state.size
    let content: ResolvedContent
    var clips = false
    // A text box is as big as its words, so it is measured here, and grows
    // from its anchor the way its alignment reads.
    var textAnchor: Vec2?

    switch layer.content {
    case .shape(let shape):
        content = .shape(resolve(shape, size: size, state: state))
    case .text(let text):
        let shown = state.text ?? ShownText(text: text.text)
        var color = text.color
        switch state.fill {
        case .solid(let c): color = c
        case .linearGradient(let g), .radialGradient(let g): color = g.stops.first?.color ?? color
        case nil: break
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
    case .image(let image):
        content = .image(mediaID: image.mediaID)
    case .video(let video):
        content = .video(mediaID: video.mediaID, sourceTime: state.sourceTime ?? 0)
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
                         mask: layer.mask.map { ResolvedMask(layerID: $0.layerID, isInverted: $0.isInverted) })
}

/// The shape with its actions applied: the first fill's paint, the first
/// stroke's width, paint and trim, and a rectangle's corners.
private func resolve(_ shape: ShapeContent, size: Size2, state: LayerState) -> ResolvedShape {
    var shape = shape
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

    let path: BezierPath
    switch shape.geometry {
    case .rectangle(let radii): path = ShapePaths.rectangle(size, radii: radii)
    case .ellipse(let arc): path = ShapePaths.ellipse(size, arc: arc)
    case .line: path = ShapePaths.line(size)
    case .polygon(let sides): path = ShapePaths.polygon(size, sides: sides)
    case .star(let points, let inner, let corner):
        path = ShapePaths.star(size, points: points, innerRadius: inner, cornerRadius: corner)
    case .path(let p): path = p
    }
    let closed = shape.geometry.isClosed

    let fills = shape.fills.filter(\.isEnabled).map { resolve($0.paint, size: size) }
    let strokes = shape.strokes.filter(\.isEnabled).map { stroke in
        ResolvedStroke(paint: resolve(stroke.paint, size: size),
                       width: max(stroke.width, 0),
                       alignment: closed ? stroke.alignment : .center,
                       cap: stroke.cap, join: stroke.join,
                       dashPattern: stroke.dashPattern.filter { $0 > 0 }, dashOffset: stroke.dashOffset,
                       trimStart: min(max(stroke.trimStart, 0), 1),
                       trimEnd: min(max(stroke.trimEnd, 0), 1))
    }
    return ResolvedShape(path: path, isClosed: closed, fills: fills, strokes: strokes)
}

private func resolve(_ paint: Paint, size: Size2) -> ResolvedPaint {
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
    }
}
