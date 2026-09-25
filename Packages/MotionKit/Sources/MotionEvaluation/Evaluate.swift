import Foundation
import MotionModel

/// Works out what the composition looks like at `time`.
///
/// A pure function: the same project and the same time always give the same
/// scene, and any time works, including between frames. The canvas, export,
/// thumbnails and (later) motion blur all call this and nothing else.
///
/// A layer is in the scene when it is switched on and `time` lies in
/// `inPoint ..< outPoint`. If any layer is soloed, only soloed layers show,
/// with everything inside a soloed group and the groups that contain a soloed
/// layer. Audio layers draw nothing and are left out, as are layers used as
/// another layer's mask.
public func evaluate(_ project: Project, at time: Double) -> ResolvedScene {
    let all = project.allLayers
    let soloing = all.contains { $0.isSoloed }
    // A layer used as another's mask stops drawing on its own. Milestone 6
    // hands mask layers to the renderer separately, to draw as masks only.
    let maskSources = Set(all.compactMap { $0.mask?.layerID })
    var out: [ResolvedLayer] = []

    func hasSoloedDescendant(_ layer: Layer) -> Bool {
        layer.children.contains { $0.isSoloed || hasSoloedDescendant($0) }
    }

    func walk(_ layers: [Layer], parent: UUID?, soloedAbove: Bool) {
        for layer in layers {
            guard layer.isVisible, time >= layer.inPoint, time < layer.outPoint,
                  !maskSources.contains(layer.id) else { continue }
            let soloed = soloedAbove || layer.isSoloed
            if soloing && !soloed && !(layer.isGroup && hasSoloedDescendant(layer)) { continue }
            guard let resolved = resolve(layer, parent: parent, at: time) else { continue }
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

private func resolve(_ layer: Layer, parent: UUID?, at t: Double) -> ResolvedLayer? {
    let size = layer.size.value(at: t)
    let content: ResolvedContent
    var clips = false

    switch layer.content {
    case .shape(let shape):
        content = .shape(resolve(shape, size: size, at: t))
    case .text(let text):
        content = .text(ResolvedText(text: text.text, fontFamily: text.fontFamily, fontWeight: text.fontWeight,
                                     fontSize: text.fontSize, color: text.color.value(at: t),
                                     alignment: text.alignment, letterSpacing: text.letterSpacing,
                                     lineHeight: text.lineHeight, sizing: text.sizing))
    case .image(let image):
        content = .image(mediaID: image.mediaID)
    case .video(let video):
        content = .video(mediaID: video.mediaID, sourceTime: video.trimStart + (t - layer.inPoint))
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
                shadow = ResolvedShadow(color: s.color.value(at: t), offset: s.offset.value(at: t),
                                        blur: max(s.blur.value(at: t), 0),
                                        opacity: min(max(s.opacity.value(at: t), 0), 1))
            }
        case .layerBlur(let b):
            blur += max(b.radius.value(at: t), 0)
        }
    }

    return ResolvedLayer(id: layer.id, parentID: parent, size: size,
                         position: layer.transform.position.value(at: t),
                         anchor: layer.transform.anchor.value(at: t),
                         scale: layer.transform.scale.value(at: t),
                         rotation: layer.transform.rotation.value(at: t),
                         opacity: min(max(layer.opacity.value(at: t), 0), 1),
                         content: content, shadow: shadow, blur: blur, clipsContent: clips,
                         mask: layer.mask.map { ResolvedMask(layerID: $0.layerID, isInverted: $0.isInverted) })
}

private func resolve(_ shape: ShapeContent, size: Size2, at t: Double) -> ResolvedShape {
    let path: BezierPath
    switch shape.geometry {
    case .rectangle(let radii): path = ShapePaths.rectangle(size, radii: radii.value(at: t))
    case .ellipse: path = ShapePaths.ellipse(size)
    case .line: path = ShapePaths.line(size)
    case .polygon(let sides): path = ShapePaths.polygon(size, sides: sides)
    case .star(let points, let inner): path = ShapePaths.star(size, points: points, innerRadius: inner.value(at: t))
    case .path(let p): path = p.value(at: t)
    }
    let closed = shape.geometry.isClosed

    let fills = shape.fills.filter(\.isEnabled).map { resolve($0.paint, size: size, at: t) }
    let strokes = shape.strokes.filter(\.isEnabled).map { stroke in
        ResolvedStroke(paint: resolve(stroke.paint, size: size, at: t),
                       width: max(stroke.width.value(at: t), 0),
                       alignment: closed ? stroke.alignment : .center,
                       cap: stroke.cap, join: stroke.join,
                       dashPattern: stroke.dashPattern.filter { $0 > 0 }, dashOffset: stroke.dashOffset,
                       trimStart: min(max(stroke.trimStart.value(at: t), 0), 1),
                       trimEnd: min(max(stroke.trimEnd.value(at: t), 0), 1))
    }
    return ResolvedShape(path: path, isClosed: closed, fills: fills, strokes: strokes)
}

private func resolve(_ paint: Paint, size: Size2, at t: Double) -> ResolvedPaint {
    func px(_ unit: Vec2) -> Vec2 { Vec2(unit.x * size.width, unit.y * size.height) }
    switch paint {
    case .solid(let color):
        return .solid(color.value(at: t))
    case .linearGradient(let g):
        return .linear(stops: g.stops.value(at: t).sorted { $0.position < $1.position },
                       start: px(g.start), end: px(g.end))
    case .radialGradient(let g):
        let center = px(g.start), edge = px(g.end)
        return .radial(stops: g.stops.value(at: t).sorted { $0.position < $1.position },
                       center: center, radius: hypot(edge.x - center.x, edge.y - center.y))
    }
}
