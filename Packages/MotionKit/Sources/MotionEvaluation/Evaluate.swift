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
    let size = state.size
    let content: ResolvedContent
    var clips = false

    switch layer.content {
    case .shape(let shape):
        content = .shape(resolve(shape, size: size))
    case .text(let text):
        content = .text(ResolvedText(text: text.text, fontFamily: text.fontFamily, fontWeight: text.fontWeight,
                                     fontSize: text.fontSize, color: text.color,
                                     alignment: text.alignment, letterSpacing: text.letterSpacing,
                                     lineHeight: text.lineHeight, sizing: text.sizing))
    case .image(let image):
        content = .image(mediaID: image.mediaID)
    case .video(let video):
        content = .video(mediaID: video.mediaID, sourceTime: video.trimStart + t)
    case .audio:
        return nil
    case .group(let group):
        content = .group
        clips = group.clipsContent
    }

    var shadow: ResolvedShadow?
    var blur = 0.0
    for effect in layer.effects where effect.isEnabled {
        switch effect.kind {
        case .dropShadow(let s):
            // One shadow per layer is what Core Animation draws. Figma allows
            // several; the first one wins until a renderer can do more.
            if shadow == nil {
                shadow = ResolvedShadow(color: s.color, offset: s.offset, blur: max(s.blur, 0),
                                        opacity: min(max(s.opacity, 0), 1))
            }
        case .layerBlur(let b):
            blur += max(b.radius, 0)
        }
    }

    // A resized layer grows around its anchor: the anchor keeps its place as
    // a fraction of the box, and the position keeps the anchor where it was.
    let designSize = layer.size
    let anchor = Vec2(designSize.width != 0 ? layer.transform.anchor.x * size.width / designSize.width : layer.transform.anchor.x,
                      designSize.height != 0 ? layer.transform.anchor.y * size.height / designSize.height : layer.transform.anchor.y)

    return ResolvedLayer(id: layer.id, parentID: parent, size: size,
                         position: state.position, anchor: anchor,
                         scale: state.scale, rotation: state.rotation,
                         opacity: min(max(state.opacity, 0), 1),
                         content: content, shadow: shadow, blur: blur, clipsContent: clips,
                         mask: layer.mask.map { ResolvedMask(layerID: $0.layerID, isInverted: $0.isInverted) })
}

private func resolve(_ shape: ShapeContent, size: Size2) -> ResolvedShape {
    let path: BezierPath
    switch shape.geometry {
    case .rectangle(let radii): path = ShapePaths.rectangle(size, radii: radii)
    case .ellipse: path = ShapePaths.ellipse(size)
    case .line: path = ShapePaths.line(size)
    case .polygon(let sides): path = ShapePaths.polygon(size, sides: sides)
    case .star(let points, let inner): path = ShapePaths.star(size, points: points, innerRadius: inner)
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
