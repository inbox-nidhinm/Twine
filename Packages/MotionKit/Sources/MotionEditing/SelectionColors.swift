import Foundation
import MotionModel

/// Figma's Selection colours (23 November 2026, the user's request): every
/// colour and gradient used inside the selection, each listed once, so a
/// group, a frame or several layers can be recoloured from one place.
///
/// What shows is what is drawn: solid fills, strokes, text colours and
/// shadows that are on, and gradients as whole gradients (their stops are
/// not listed as colours, as in Figma). Changing one changes it everywhere
/// it is used under the selection, and also where it is used but hidden (a
/// fill or shadow switched off) and in the actions on those layers that
/// change to it or start from it, so a Colour action does not go back to
/// the old colour.
public enum SelectionColors {
    /// One place a colour or gradient is kept.
    public enum Place: Hashable, Sendable {
        case fill(layer: UUID, id: UUID)
        case stroke(layer: UUID, id: UUID)
        case textColor(layer: UUID)
        case textStroke(layer: UUID)
        /// A drop or inner shadow's colour.
        case shadow(layer: UUID, id: UUID)
        /// An action's starting value.
        case actionStart(UUID)
        /// An action's end value.
        case actionEnd(UUID)
    }

    /// A colour or a gradient used in the selection, where it is used.
    public struct Entry: Equatable, Sendable, Identifiable {
        public enum Look: Equatable, Sendable {
            case color(RGBA)
            case gradient(Gradient, GradientKind)
        }

        public var look: Look
        /// Where it is kept, the first place first: drawn ones, then
        /// hidden ones and actions.
        public var places: [Place]

        /// Its first place, which stays the same while it is edited.
        public var id: Place { places[0] }
    }

    /// The colours and gradients used by `ids` and everything inside them,
    /// in the order they are met going down the layers panel (front first,
    /// a layer's fills top first, then its strokes, text and shadows).
    /// Colours less than a step of 255 apart in every channel count as one;
    /// gradients count as one when their kind and stops match.
    public static func entries(in project: Project, under ids: [UUID]) -> [Entry] {
        var entries: [Entry] = []
        var index: [Key: Int] = [:]
        var followers: [(Key, Place)] = []
        var layerIDs = Set<UUID>()

        func add(_ paint: Paint, at place: Place, drawn: Bool) {
            switch paint {
            case .solid(let c): add(c, at: place, drawn: drawn)
            case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g):
                let kind = paint.gradientKind ?? .linear
                let key = Key.gradient(kind, g.stops.sorted { $0.position < $1.position }.map(StopKey.init))
                note(key, .gradient(g, kind), place, drawn)
            case .image: break
            }
        }
        func add(_ color: RGBA, at place: Place, drawn: Bool) {
            note(.color(ColorKey(color)), .color(color), place, drawn)
        }
        func note(_ key: Key, _ look: Entry.Look, _ place: Place, _ drawn: Bool) {
            guard drawn else {
                followers.append((key, place))
                return
            }
            if let i = index[key] {
                entries[i].places.append(place)
            } else {
                index[key] = entries.count
                entries.append(Entry(look: look, places: [place]))
            }
        }
        func visit(_ layer: Layer) {
            layerIDs.insert(layer.id)
            let id = layer.id
            switch layer.content {
            case .shape, .group:
                if let look = layer.look {
                    for fill in look.fills.reversed() {
                        add(fill.paint, at: .fill(layer: id, id: fill.id), drawn: fill.isEnabled)
                    }
                    for stroke in look.strokes.reversed() {
                        add(stroke.paint, at: .stroke(layer: id, id: stroke.id), drawn: stroke.isEnabled)
                    }
                }
            case .text(let text):
                add(text.color, at: .textColor(layer: id), drawn: text.showsFill)
                if let stroke = text.stroke {
                    add(stroke.paint, at: .textStroke(layer: id), drawn: stroke.isEnabled)
                }
            case .video, .audio: break
            }
            for effect in layer.effects {
                switch effect.kind {
                case .dropShadow(let s), .innerShadow(let s):
                    add(s.color, at: .shadow(layer: id, id: effect.id), drawn: effect.isEnabled)
                case .layerBlur, .backgroundBlur, .glass: break
                }
            }
            // Front first, as the layers panel lists them.
            if layer.isGroup { layer.children.reversed().forEach(visit) }
        }

        for id in outermost(ids, in: project) {
            if let layer = project.layer(withID: id) { visit(layer) }
        }
        for action in project.actions where layerIDs.contains(action.targetLayerID) {
            let id = action.id
            switch action.spec {
            case .color(let c):
                if let initial = c.initial { add(initial, at: .actionStart(id), drawn: false) }
                add(c.end, at: .actionEnd(id), drawn: false)
            case .stroke(let s):
                if let initial = s.initial { add(initial.paint, at: .actionStart(id), drawn: false) }
                add(s.end.paint, at: .actionEnd(id), drawn: false)
            case .shadow(let s), .innerShadow(let s):
                if let initial = s.initial { add(initial.color, at: .actionStart(id), drawn: false) }
                add(s.end.color, at: .actionEnd(id), drawn: false)
            default: break
            }
        }
        // Hidden paints and actions follow a colour that shows, and are not
        // listed on their own.
        for (key, place) in followers {
            if let i = index[key] { entries[i].places.append(place) }
        }
        return entries
    }

    /// Every place in `places` set to `color`, as one undo step; nil when
    /// none of them can be found.
    public static func setting(_ places: [Place], to color: RGBA, in project: Project) -> EditorCommand? {
        edit(places, in: project, name: "Selection Colour") { paint in
            paint.isGradientOrImage ? paint : .solid(color)
        } color: { _ in color }
    }

    /// Every gradient in `places` given `gradient`'s stops, each keeping its
    /// own kind, direction and size, as one undo step.
    public static func setting(_ places: [Place], toStopsOf gradient: Gradient, in project: Project) -> EditorCommand? {
        edit(places, in: project, name: "Selection Gradient") { paint in
            guard var g = paint.gradient else { return paint }
            g.stops = gradient.stops
            return paint.withGradient(g)
        } color: { $0 }
    }

    // MARK: Changing

    private static func edit(_ places: [Place], in project: Project, name: String,
                             paint change: (Paint) -> Paint, color recolor: (RGBA) -> RGBA) -> EditorCommand? {
        var p = project
        var changedLayers = Set<UUID>()
        var actions: [UUID: Action] = [:]

        for place in places {
            switch place {
            case .fill(let layer, let id):
                let found = p.updateLayer(layer) { l in
                    guard var look = l.look, let i = look.fills.firstIndex(where: { $0.id == id }) else { return }
                    look.fills[i].paint = change(look.fills[i].paint)
                    l.look = look
                }
                if found { changedLayers.insert(layer) }
            case .stroke(let layer, let id):
                let found = p.updateLayer(layer) { l in
                    guard var look = l.look, let i = look.strokes.firstIndex(where: { $0.id == id }) else { return }
                    look.strokes[i].paint = change(look.strokes[i].paint)
                    l.look = look
                }
                if found { changedLayers.insert(layer) }
            case .textColor(let layer):
                let found = p.updateLayer(layer) { l in
                    guard case .text(var t) = l.content else { return }
                    t.color = recolor(t.color)
                    l.content = .text(t)
                }
                if found { changedLayers.insert(layer) }
            case .textStroke(let layer):
                let found = p.updateLayer(layer) { l in
                    guard case .text(var t) = l.content, var stroke = t.stroke else { return }
                    stroke.paint = change(stroke.paint)
                    t.stroke = stroke
                    l.content = .text(t)
                }
                if found { changedLayers.insert(layer) }
            case .shadow(let layer, let id):
                let found = p.updateLayer(layer) { l in
                    guard let i = l.effects.firstIndex(where: { $0.id == id }) else { return }
                    switch l.effects[i].kind {
                    case .dropShadow(var s):
                        s.color = recolor(s.color)
                        l.effects[i].kind = .dropShadow(s)
                    case .innerShadow(var s):
                        s.color = recolor(s.color)
                        l.effects[i].kind = .innerShadow(s)
                    case .layerBlur, .backgroundBlur, .glass: break
                    }
                }
                if found { changedLayers.insert(layer) }
            case .actionStart(let id), .actionEnd(let id):
                guard var action = actions[id] ?? project.actions.first(where: { $0.id == id }) else { continue }
                let start = if case .actionStart = place { true } else { false }
                switch action.spec {
                case .color(var c):
                    if start { c.initial = c.initial.map(change) } else { c.end = change(c.end) }
                    action.spec = .color(c)
                case .stroke(var s):
                    if start { s.initial = s.initial.map { StrokeLook(width: $0.width, paint: change($0.paint)) } } else { s.end.paint = change(s.end.paint) }
                    action.spec = .stroke(s)
                case .shadow(var s):
                    if let initial = s.initial, start { s.initial?.color = recolor(initial.color) } else if !start { s.end.color = recolor(s.end.color) }
                    action.spec = .shadow(s)
                case .innerShadow(var s):
                    if let initial = s.initial, start { s.initial?.color = recolor(initial.color) } else if !start { s.end.color = recolor(s.end.color) }
                    action.spec = .innerShadow(s)
                default: break
                }
                actions[id] = action
            }
        }

        // Each changed layer goes in whole with its children, so only the
        // outermost ones are handed over: a group handed over after one of
        // its children would put the child's old self back.
        var layers: [Layer] = []
        func collect(_ list: [Layer]) {
            for layer in list {
                if changedLayers.contains(layer.id) {
                    layers.append(layer)
                } else if layer.isGroup {
                    collect(layer.children)
                }
            }
        }
        collect(p.layers)

        var commands: [EditorCommand] = []
        if !layers.isEmpty { commands.append(.updateLayers(layers)) }
        if !actions.isEmpty {
            commands.append(.updateActions(project.actions.compactMap { actions[$0.id] }))
        }
        return commands.isEmpty ? nil : .batch(commands, name: name)
    }

    /// `ids` without any layer that sits inside another of them, so nothing
    /// is counted twice.
    private static func outermost(_ ids: [UUID], in project: Project) -> [UUID] {
        let picked = Set(ids)
        var out: [UUID] = []
        func walk(_ list: [Layer], inside: Bool) {
            for layer in list {
                let isPicked = picked.contains(layer.id)
                if isPicked && !inside { out.append(layer.id) }
                if layer.isGroup { walk(layer.children, inside: inside || isPicked) }
            }
        }
        walk(project.layers, inside: false)
        return out
    }

    // MARK: Keys

    private enum Key: Hashable {
        case color(ColorKey)
        case gradient(GradientKind, [StopKey])
    }

    /// A colour to the nearest step of 255 in each channel, opacity included.
    private struct ColorKey: Hashable {
        let r, g, b, a: Int

        init(_ c: RGBA) {
            func step(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
            r = step(c.r); g = step(c.g); b = step(c.b); a = step(c.a)
        }
    }

    private struct StopKey: Hashable {
        let color: ColorKey
        let position: Int

        init(_ stop: GradientStop) {
            color = ColorKey(stop.color)
            position = Int((stop.position * 1000).rounded())
        }
    }
}

private extension Paint {
    var isGradientOrImage: Bool {
        if case .solid = self { return false }
        return true
    }
}
