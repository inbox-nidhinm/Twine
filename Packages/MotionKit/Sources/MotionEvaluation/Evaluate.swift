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
///
/// A layer moved by an action with motion blur on carries `motion`: where
/// to draw it across the shutter, at `motionBlur`'s quality.
public func evaluate(_ project: Project, at time: Double,
                     motionBlur quality: MotionBlurQuality = .preview, cache: EvaluationCache? = nil) -> ResolvedScene {
    scene(of: project, at: time, tracks: cache?.tracks(for: project.actions) ?? ActionTracks(project.actions),
          blur: MotionContext(samples: quality.samples, frame: project.composition.frameRate.frameDuration,
                              exact: quality == .export),
          cache: cache)
}

/// What one evaluation can hand the next: the tracks, while the actions are
/// the same, and every layer no action reaches as it was resolved, while
/// the layer is the same. In a large project most layers never move, and
/// working each out again every frame was most of the time a frame took
/// (5,000 layers with 550 actions: 9.4 ms a frame).
///
/// One per caller (the canvas, an export), on one thread at a time.
public final class EvaluationCache {
    private var actions: [Action]?
    private var madeTracks = ActionTracks([])
    private var pictures: [UUID: Size2] = [:]
    private var entries: [UUID: Entry] = [:]
    private var runs: [UUID: Run] = [:]
    /// Which evaluation each entry was last used by, so entries for layers
    /// that went are let go.
    private var generation = 0
    private var used = 0
    private var runsUsed = 0

    /// A class, so looking one up copies nothing: copying the layer and
    /// its resolved self out of the table for every layer cost more than
    /// resolving it.
    private final class Entry {
        /// The layer as it was, without a group's children, which its own
        /// resolved layer never reads.
        let layer: Layer
        let parent: UUID?
        let resolved: ResolvedLayer?
        var generation: Int

        init(layer: Layer, parent: UUID?, resolved: ResolvedLayer?, generation: Int) {
            self.layer = layer
            self.parent = parent
            self.resolved = resolved
            self.generation = generation
        }
    }

    /// A still group with everything inside it, in drawing order.
    private final class Run {
        let layer: Layer
        let parent: UUID?
        let resolved: [ResolvedLayer]
        var generation: Int

        init(layer: Layer, parent: UUID?, resolved: [ResolvedLayer], generation: Int) {
            self.layer = layer
            self.parent = parent
            self.resolved = resolved
            self.generation = generation
        }
    }

    public init() {}

    /// Comparing lists that were never changed since is immediate: they
    /// share their storage.
    func tracks(for actions: [Action]) -> ActionTracks {
        if actions != self.actions {
            self.actions = actions
            madeTracks = ActionTracks(actions)
        }
        return madeTracks
    }

    func begin(pictures: [UUID: Size2]) {
        if pictures != self.pictures {
            self.pictures = pictures
            entries.removeAll(keepingCapacity: true)
            runs.removeAll(keepingCapacity: true)
        }
        generation += 1
        used = 0
        runsUsed = 0
    }

    func end() {
        if runs.count > runsUsed * 2 + 64 {
            runs = runs.filter { $0.value.generation == generation }
        }
        guard entries.count > used * 2 + 64 else { return }
        entries = entries.filter { $0.value.generation == generation }
    }

    /// A still group and everything in it, as resolved last time, when it
    /// and everything in it are the same.
    func run(of group: Layer, parent: UUID?) -> [ResolvedLayer]? {
        guard let entry = runs[group.id], entry.parent == parent, entry.layer == group else { return nil }
        entry.generation = generation
        used += entry.resolved.count
        runsUsed += 1
        return entry.resolved
    }

    func keep(_ run: [ResolvedLayer], of group: Layer, parent: UUID?) {
        runsUsed += 1
        runs[group.id] = Run(layer: group, parent: parent, resolved: run, generation: generation)
    }

    /// `layer` resolved as designed, from the last evaluation when it has
    /// not changed since, else by `make`.
    func resolved(_ layer: Layer, parent: UUID?, _ make: () -> ResolvedLayer?) -> ResolvedLayer? {
        used += 1
        let entry = entries[layer.id]
        // Only a group is copied, to leave its children out.
        if layer.isGroup, case .group(var group) = layer.content, !group.children.isEmpty {
            group.children = []
            var key = layer
            key.content = .group(group)
            if let entry, entry.parent == parent, entry.layer == key {
                entry.generation = generation
                return entry.resolved
            }
            let made = make()
            entries[layer.id] = Entry(layer: key, parent: parent, resolved: made, generation: generation)
            return made
        }
        if let entry, entry.parent == parent, entry.layer == layer {
            entry.generation = generation
            return entry.resolved
        }
        let made = make()
        entries[layer.id] = Entry(layer: layer, parent: parent, resolved: made, generation: generation)
        return made
    }
}

/// What motion blur needs to know: how many copies, how long a frame is,
/// which the shutter is a share of, and whether each moment is wanted
/// exactly.
struct MotionContext {
    let samples: Int
    let frame: Double
    let exact: Bool

    /// `spread` as asked for: the step and copies, or when steady and
    /// wanted exactly, every moment worked out by `placed`.
    func finish(_ spread: MotionSpread, first: Double, shutter: Double, _ placed: (Double) -> Projective) -> MotionSpread {
        guard exact, case .spread = spread else { return spread }
        return .exact((0..<samples).map { placed(first + shutter * Double($0) / Double(samples - 1)) })
    }
}

/// The composition as designed, with no actions applied: what Design mode
/// shows.
public func evaluateDesign(_ project: Project, cache: EvaluationCache? = nil) -> ResolvedScene {
    scene(of: project, at: 0, tracks: ActionTracks([]), blur: nil, cache: cache)
}

private func scene(of project: Project, at time: Double, tracks: ActionTracks, blur: MotionContext?,
                   cache: EvaluationCache?) -> ResolvedScene {
    // Only worked out when some action has it, so a scene without costs one check.
    let blur = blur.flatMap { $0.samples > 1 && tracks.hasMotionBlur ? $0 : nil }
    // Whether anything is soloed, and the layers that are masks, which do
    // not draw on their own but only through the layers in front of them
    // that they mask. Found in one pass that copies no layers.
    var soloing = false
    var maskSources = Set<UUID>()
    var count = 0
    func note(_ layers: [Layer]) {
        // By place rather than `for in`, which copies every layer.
        for i in layers.indices {
            if layers[i].isSoloed { soloing = true }
            if layers[i].isMask { maskSources.insert(layers[i].id) }
            if layers[i].isGroup { note(layers[i].children) }
        }
        count += layers.count
    }
    note(project.layers)
    let pictures = project.pictureSizes
    cache?.begin(pictures: pictures)
    defer { cache?.end() }
    var out: [ResolvedLayer] = []
    out.reserveCapacity(count)
    /// The masks of the layers in `out`, by their place there, noted on the
    /// way rather than looked up afterwards: that searched the whole
    /// project for every layer, every frame, once any mask existed.
    var masked: [(index: Int, mask: UUID)] = []

    func hasSoloedDescendant(_ layer: Layer) -> Bool {
        layer.children.contains { $0.isSoloed || hasSoloedDescendant($0) }
    }

    /// The groups whose every layer, themselves included, no action reaches
    /// and no mask touches: what they resolve to can only change with them.
    var stillGroups = Set<UUID>()
    if cache != nil, !soloing {
        @discardableResult
        func still(_ layers: [Layer]) -> Bool {
            var all = true
            // Everything in front of a mask is masked by it.
            var behindAMask = false
            for i in layers.indices {
                if layers[i].isMask { behindAMask = true }
                var mine = tracks.isStill(layers[i].id) && !behindAMask
                if layers[i].isGroup {
                    mine = still(layers[i].children) && mine
                    if mine { stillGroups.insert(layers[i].id) }
                }
                all = all && mine
            }
            return all
        }
        still(project.layers)
    }

    func walk(_ layers: [Layer], parent: UUID?, soloedAbove: Bool) {
        // The mask behind the layers so far in this list: each masks the
        // ones in front of it up to the next, as in Figma. A hidden mask
        // still ends the one before; it masks nothing (see below).
        var mask: UUID?
        for layer in layers {
            if layer.isMask { mask = layer.id }
            guard layer.isVisible, !maskSources.contains(layer.id) else { continue }
            let soloed = soloedAbove || layer.isSoloed
            if soloing && !soloed && !(layer.isGroup && hasSoloedDescendant(layer)) { continue }
            // A still group the same as last time, children and all, is
            // what it was then. Lists never changed since compare at once.
            let first = out.count
            let whole = cache != nil && stillGroups.contains(layer.id)
            if whole, let run = cache?.run(of: layer, parent: parent) {
                out.append(contentsOf: run)
                continue
            }
            defer { if whole { cache?.keep(Array(out[first...]), of: layer, parent: parent) } }
            let made: ResolvedLayer?
            if let cache, tracks.isStill(layer.id) {
                made = cache.resolved(layer, parent: parent) {
                    resolve(layer, state: LayerState(design: layer), parent: parent, pictures: pictures,
                            animation: nil, time: time)
                }
            } else {
                let state = tracks.state(of: layer, at: time)
                // Hidden by an action: the layer and everything inside it.
                guard state.isShown else { continue }
                made = resolve(layer, state: state, parent: parent, pictures: pictures,
                               animation: tracks.textAnimation(of: layer, at: time), time: time, blur: blur)
            }
            guard var resolved = made else { continue }
            if let blur { resolved.motion = motion(of: layer, resolved, tracks: tracks, at: time, blur) }
            if let mask { masked.append((out.count, mask)) }
            out.append(resolved)
            if layer.isGroup { walk(layer.children, parent: layer.id, soloedAbove: soloed) }
        }
    }
    walk(project.layers, parent: nil, soloedAbove: false)

    if !maskSources.isEmpty {
        let all = project.allLayers
        var world = WorldTransforms(all: all, tracks: tracks, time: time, pictures: pictures, known: out)
        var masks: [ResolvedLayer] = []
        for id in maskSources {
            guard let layer = world.resolved(id) else { continue }
            var source = layer
            // A mask draws alone; its own mask is not followed.
            source.mask = nil
            masks.append(source)
        }
        let shown = Set(masks.map(\.id))
        for (i, mask) in masked {
            if shown.contains(mask), let from = world.transform(of: mask), let into = world.transform(of: out[i].id)?.inverted {
                out[i].mask = ResolvedMask(layerID: mask, transform: from.then(into))
            } else {
                out[i].mask = nil
            }
        }
        // In drawing order, so the scene is the same whatever order the set
        // gives.
        // A damaged file may repeat an id; the first place counts.
        let order = Dictionary(all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
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
    let tracks: ActionTracks
    let time: Double
    let pictures: [UUID: Size2]
    private var cache: [UUID: ResolvedLayer?] = [:]
    /// Every layer and its parent, found once rather than by searching the
    /// tree for each mask.
    private var layers: [UUID: Layer] = [:]
    private var parents: [UUID: UUID] = [:]

    init(all: [Layer], tracks: ActionTracks, time: Double, pictures: [UUID: Size2], known: [ResolvedLayer]) {
        self.tracks = tracks
        self.time = time
        self.pictures = pictures
        for layer in known { cache[layer.id] = layer }
        for layer in all {
            if layers[layer.id] == nil { layers[layer.id] = layer }
            for child in layer.children { parents[child.id] = layer.id }
        }
    }

    /// The layer as it stands at `time`, or nil if it, or a group it sits
    /// in, is switched off or hidden.
    mutating func resolved(_ id: UUID) -> ResolvedLayer? {
        if let known = cache[id] { return known }
        var result: ResolvedLayer?
        let parent = parents[id]
        if let layer = layers[id], layer.isVisible, parent.map({ resolved($0) != nil }) ?? true {
            let state = tracks.state(of: layer, at: time)
            if state.isShown {
                result = resolve(layer, state: state, parent: parent, pictures: pictures,
                                 animation: tracks.textAnimation(of: layer, at: time), time: time)
            }
        }
        cache[id] = result
        return result
    }

    mutating func transform(of id: UUID) -> Projective? {
        guard let layer = resolved(id) else { return nil }
        guard let parent = layer.parentID else { return layer.projection }
        return transform(of: parent).map { layer.projection.then($0) }
    }
}

/// Where motion blur draws `layer`'s copies at `time`: across the shutter of
/// the actions with it on, with only the channels they drive spread and the
/// rest held as they are at `time`, so a layer that also fades or turns by
/// another action does so sharply.
private func motion(of layer: Layer, _ resolved: ResolvedLayer, tracks: ActionTracks, at time: Double,
                    _ blur: MotionContext) -> MotionSpread {
    guard let (channels, shutter) = tracks.motionBlur(of: layer.id, at: time, frame: blur.frame) else { return .none }
    let first = time - shutter / 2
    func placed(at t: Double) -> Projective {
        let state = tracks.state(of: layer, at: t)
        var moved = resolved
        if channels.contains(.position) { moved.position = state.position }
        if channels.contains(.scale) { moved.scale = state.scale }
        if channels.contains(.rotation) { moved.rotation = state.rotation }
        if channels.contains(.skew) || channels.contains(.tilt) {
            moved.warp = Warp(skew: channels.contains(.skew) ? state.warp.skew : resolved.skew,
                              tilt: channels.contains(.tilt) ? state.warp.tilt : resolved.tilt)
        }
        return moved.projection
    }
    let spread = MotionSpread(first: placed(at: first), next: placed(at: first + shutter / Double(blur.samples - 1)),
                              last: placed(at: first + shutter), count: blur.samples, size: resolved.size)
    return blur.finish(spread, first: first, shutter: shutter, placed(at:))
}

private func resolve(_ layer: Layer, state: LayerState, parent: UUID?, pictures: [UUID: Size2],
                     animation: TextAnimation?, time: Double, blur: MotionContext? = nil) -> ResolvedLayer? {
    var size = state.size
    let content: ResolvedContent
    var clips = false
    var frame: ResolvedShape?
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
        case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g): color = g.stops.first?.color ?? color
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
        var drawn = resolved
        drawn.showsFill = text.showsFill
        // A Stroke action drives the width and colour, as on a shape.
        if let stroke = text.stroke, stroke.isEnabled, (state.stroke?.width ?? stroke.width) > 0 {
            let look = state.stroke ?? StrokeLook(stroke)
            let color: RGBA
            switch look.paint {
            case .solid(let c): color = c
            case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g): color = g.stops.first?.color ?? .black
            case .image: color = .black
            }
            drawn.stroke = ResolvedTextStroke(color: color, width: look.width, alignment: stroke.alignment, join: stroke.join)
        }
        if let animation {
            drawn.units = units(of: shown.text, style: resolved.style, width: width, animation, at: time, blur: blur)
        }
        content = .text(drawn)
    case .video(let video):
        content = .video(mediaID: video.mediaID, sourceTime: state.sourceTime ?? 0, fit: video.fit)
    case .audio:
        return nil
    case .group(let group):
        content = .group
        clips = group.clipsContent
        if let look = layer.look { frame = resolve(look, size: size, state: state, pictures: pictures) }
    }

    // Every drop shadow switched on, in order; the first carries the
    // Shadow action, which on a layer designed without one is the only one.
    // Inner shadows fall inside an outline, so only shapes and frames have
    // them; the first carries the Inner Shadow action the same way. The first background blur counts, as in Figma; layer blurs add
    // up, the first carrying its action.
    func shown(_ s: DropShadow) -> ResolvedShadow? {
        guard s.opacity > 0, s.color.a > 0 else { return nil }
        return ResolvedShadow(color: s.color, offset: s.offset, blur: max(s.blur, 0),
                              opacity: min(max(s.opacity, 0), 1), spread: s.spread)
    }
    var shadows: [ResolvedShadow] = []
    var innerShadows: [ResolvedShadow] = []
    var drivenShadow = false
    var drivenInner = false
    for effect in layer.effects where effect.isEnabled {
        switch effect.kind {
        case .dropShadow(let s):
            if drivenShadow { shown(s).map { shadows.append($0) } } else { shown(state.shadow).map { shadows.append($0) } }
            drivenShadow = true
        case .innerShadow(let s):
            if layer.look != nil { shown(drivenInner ? s : state.innerShadow.shadow).map { innerShadows.append($0) } }
            drivenInner = true
        case .layerBlur, .backgroundBlur:
            break
        }
    }
    if !drivenShadow { shown(state.shadow).map { shadows.append($0) } }
    if !drivenInner, layer.look != nil { shown(state.innerShadow.shadow).map { innerShadows.append($0) } }
    var blur = max(state.layerBlur, 0)
    let blurs = layer.effects.filter(\.isEnabled).compactMap { effect -> Double? in
        if case .layerBlur(let b) = effect.kind { return b.radius }
        return nil
    }
    blur += blurs.dropFirst().reduce(0) { $0 + max($1, 0) }
    var backgroundBlur: BackgroundBlur?
    if layer.look != nil, state.backgroundBlur.radius > 0, state.backgroundBlur.blend > 0 {
        backgroundBlur = state.backgroundBlur
    }

    // A resized layer grows around its anchor: the anchor keeps its place as
    // a fraction of the box, and the position keeps the anchor where it was.
    let designSize = layer.size
    let anchor = textAnchor ?? Vec2(designSize.width != 0 ? layer.transform.anchor.x * size.width / designSize.width : layer.transform.anchor.x,
                      designSize.height != 0 ? layer.transform.anchor.y * size.height / designSize.height : layer.transform.anchor.y)

    var resolved = ResolvedLayer(id: layer.id, parentID: parent, size: size,
                         position: state.position, anchor: anchor,
                         scale: state.scale, rotation: state.rotation,
                         opacity: min(max(state.opacity, 0), 1),
                         content: content, shadows: shadows, innerShadows: innerShadows, blendMode: layer.blendMode,
                         blur: blur, backgroundBlur: backgroundBlur,
                         clipsContent: clips, frame: frame,
                         // Filled in once every layer is resolved, since a
                         // mask can sit anywhere in the tree.
                         mask: nil, warp: state.warp)
    resolved.reveal = state.reveal
    if state.curl.isGone { resolved.opacity = 0 } else { resolved.curl = state.curl }
    return resolved
}

/// A text's letters, words or lines as a text preset has them at `time`,
/// each placed from its own centre. Empty when every one is at rest, so a
/// finished preset draws the text whole again.
private func units(of text: String, style: TextStyle, width: Double?, _ animation: TextAnimation,
                   at time: Double, blur: MotionContext?) -> [ResolvedTextUnit] {
    let spans = TextSpans.spans(animation.unit, of: text, style: style, width: width)
    let states = animation.states(count: spans.count, at: time)
    guard states.contains(where: { $0 != TextAnimation.rest }) else { return [] }
    func placed(_ span: TextSpan, _ state: LayerState) -> Projective {
        let centre = Vec2(span.box.width / 2, span.box.height / 2)
        return Projective.layer(position: span.box.center + state.position, anchor: centre,
                                scale: state.scale, rotation: state.rotation, skew: state.skew, tilt: state.tilt,
                                size: Size2(span.box.width, span.box.height))
    }
    var units = zip(spans, states).map { span, state in
        ResolvedTextUnit(range: span.range, box: span.box, transform: placed(span, state),
                         opacity: state.isShown ? min(max(state.opacity, 0), 1) : 0,
                         blur: max(state.layerBlur, 0), reveal: state.reveal)
    }
    // Each letter blurs by its own motion, across the bar's shutter.
    let action = animation.preset.action
    if let blur, let amount = action.motionBlur, amount > 0 {
        let shutter = amount * blur.frame
        if action.start < time + shutter / 2, action.end > time - shutter / 2 {
            let first = time - shutter / 2
            let from = animation.states(count: spans.count, at: first)
            let next = animation.states(count: spans.count, at: first + shutter / Double(blur.samples - 1))
            let last = animation.states(count: spans.count, at: first + shutter)
            let moments = blur.exact
                ? (0..<blur.samples).map { animation.states(count: spans.count, at: first + shutter * Double($0) / Double(blur.samples - 1)) }
                : []
            for i in units.indices {
                let spread = MotionSpread(first: placed(spans[i], from[i]), next: placed(spans[i], next[i]),
                                          last: placed(spans[i], last[i]), count: blur.samples,
                                          size: Size2(spans[i].box.width, spans[i].box.height))
                units[i].motion = blur.finish(spread, first: first, shutter: shutter) { t in
                    let k = Int(((t - first) / shutter * Double(blur.samples - 1)).rounded())
                    return placed(spans[i], moments[min(max(k, 0), moments.count - 1)][i])
                }
            }
        }
    }
    return units
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
    if let fill = state.fill, let top = shape.topFillIndex { shape.fills[top].paint = fill }
    if !shape.strokes.isEmpty {
        if let look = state.stroke {
            shape.strokes[0].width = look.width
            shape.strokes[0].paint = look.paint
        }
        if let trim = state.trim { shape.strokes[0].trim = trim }
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
    let strokes = shape.strokes.indices.filter { shape.strokes[$0].isEnabled && !shape.strokes[$0].paint.isImage }.map { i in
        let stroke = shape.strokes[i]
        // Dash actions move the first stroke's dashes.
        let travel = i == 0 ? state.dash : .still
        let width = max(stroke.width, 0)
        // A dot is a dash of no length with round ends, the gap the clear
        // space between dots.
        let pattern = stroke.dotted ? [0, max(stroke.gap, 0) + width] : stroke.dashPattern.filter { $0 > 0 }
        let period = pattern.reduce(0, +)
        // Travelling forward is the pattern moving towards the path's end
        // (or, following the trim, each stretch's growing tip), which a
        // falling phase gives.
        var phase = stroke.dashOffset - travel.distance
        if period > 0 { phase = phase.truncatingRemainder(dividingBy: period); if phase < 0 { phase += period } }
        let trim = stroke.trim
        let trimmed = trim == .whole && !travel.followsTrim ? nil : PathTrim.trimmed(path, trim, growing: travel.followsTrim)
        return ResolvedStroke(paint: resolve(stroke.paint, size: size, pictures: pictures),
                              width: width,
                              alignment: closed ? stroke.alignment : .center,
                              cap: stroke.dotted ? .round : stroke.cap, join: stroke.join,
                              dashPattern: pattern, dashOffset: phase,
                              trimmed: trimmed?.path, dashStarts: trimmed?.starts ?? [])
    }
    return ResolvedShape(path: path, isClosed: closed, fillRule: shape.fillRule, fills: fills, strokes: strokes)
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
    case .angularGradient(let g):
        return .angular(stops: g.stops.sorted { $0.position < $1.position }, center: px(g.start), toward: px(g.end))
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
