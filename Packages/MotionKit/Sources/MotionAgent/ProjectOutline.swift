import Foundation
import MotionModel
import MotionEvaluation
import MotionEditing

/// The project as an AI reads it: a short outline of every layer and
/// action, and the exact file JSON of whatever it asks to see whole.
enum ProjectOutline {
    /// Two places, which is finer than a pixel and keeps the outline short.
    static func number(_ x: Double) -> JSONValue { .number((x * 100).rounded() / 100) }

    static func composition(_ c: Composition) -> JSONValue {
        [
            "width": .number(Double(c.width)), "height": .number(Double(c.height)),
            "duration": number(c.duration), "fps": number(Double(c.frameRate.frames) / Double(c.frameRate.seconds)),
            "background": .string(c.background.color.agentHex),
            "transparent": .bool(c.background.isTransparent),
        ]
    }

    static func project(_ p: Project) -> JSONValue {
        [
            "composition": composition(p.composition),
            "layers": .array(p.layers.reversed().map(layer)),
            "actions": .array(ActionEditing.timeline(in: p).map(action)),
            "scenes": .array(p.scenes.map { scene in
                ["id": .string(scene.id.uuidString), "name": .string(scene.name),
                 "action_ids": .array(scene.actionIDs.map { .string($0.uuidString) })]
            }),
        ]
    }

    static func kind(of layer: Layer) -> String {
        switch layer.content {
        case .shape(let s):
            switch s.geometry {
            case .rectangle: return s.fills.last?.paint.isImage == true ? "picture" : "rectangle"
            case .ellipse: return "ellipse"
            case .line: return "line"
            case .polygon: return "polygon"
            case .star: return "star"
            case .path: return "path"
            }
        case .text: return "text"
        case .video: return "video"
        case .audio: return "audio"
        case .group(let g): return g.template != nil ? "template" : g.frame != nil ? "frame" : "group"
        }
    }

    /// Where the layer's box starts in its parent: its top-left corner as
    /// drawn, turns and all.
    static func topLeft(of layer: Layer) -> Vec2 {
        let t = layer.transform
        return Affine.layer(position: t.position, anchor: t.anchor, scale: t.scale, rotation: t.rotation, skew: t.skew)
            .apply(.zero)
    }

    /// One layer and its children, front first as the layers panel lists them.
    static func layer(_ layer: Layer) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(layer.id.uuidString), "name": .string(layer.name), "type": .string(kind(of: layer)),
        ]
        let corner = topLeft(of: layer)
        o["x"] = number(corner.x)
        o["y"] = number(corner.y)
        o["width"] = number(layer.size.width)
        o["height"] = number(layer.size.height)
        let t = layer.transform
        if t.rotation != 0 { o["rotation"] = number(t.rotation) }
        if t.scale != Vec2(1, 1) { o["scale"] = [number(t.scale.x), number(t.scale.y)] }
        if t.z != 0 { o["z"] = number(t.z) }
        if layer.opacity != 1 { o["opacity"] = number(layer.opacity) }
        if !layer.isVisible { o["hidden"] = true }
        if layer.isLocked { o["locked"] = true }
        if layer.isMask { o["mask"] = true }
        if layer.blendMode != .normal { o["blend_mode"] = .string(layer.blendMode.rawValue) }
        if let look = layer.look {
            if let top = look.fills.last(where: \.isEnabled) { o["fill"] = .string(paintName(top.paint)) }
            if let stroke = look.strokes.first(where: \.isEnabled) {
                o["stroke"] = .string(paintName(stroke.paint))
                o["stroke_width"] = number(stroke.width)
            }
        }
        if !layer.effects.isEmpty { o["effects"] = .array(layer.effects.map { .string($0.kind.agentName) }) }
        switch layer.content {
        case .text(let text):
            o["text"] = .string(text.text)
            o["font"] = .string("\(text.fontFamily) \(text.fontWeight) \(Int(text.fontSize.rounded()))")
            o["color"] = .string(text.color.agentHex)
        case .group(let g):
            if let template = g.template { o["template"] = .string(template.kind.rawValue) }
            if g.frame?.space != nil { o["is_3d"] = true }
            if !g.children.isEmpty { o["children"] = .array(g.children.reversed().map(self.layer)) }
        default: break
        }
        return .object(o)
    }

    static func paintName(_ paint: Paint) -> String {
        switch paint {
        case .solid(let c): return c.agentHex
        case .linearGradient: return "linear gradient"
        case .radialGradient: return "radial gradient"
        case .angularGradient: return "angular gradient"
        case .image: return "picture"
        }
    }

    /// One action, with its values as the file keeps them (bar a path's
    /// points, which are long; `get_project` with its id gives them).
    static func action(_ a: Action) -> JSONValue {
        var o: [String: JSONValue] = [
            "id": .string(a.id.uuidString), "layer_id": .string(a.targetLayerID.uuidString),
            "name": .string(a.name), "kind": .string(a.spec.kind.rawValue),
            "start": number(a.start), "duration": number(a.duration),
            "easing": easing(a.easing),
        ]
        if !a.isEnabled { o["enabled"] = false }
        if let blur = a.motionBlur { o["motion_blur"] = number(blur) }
        if a.spec.kind != .path, let values = (try? JSONValue.encoding(a.spec))?[a.spec.kind.rawValue] {
            o["values"] = values
        }
        return .object(o)
    }

    static func easing(_ e: Easing) -> JSONValue {
        switch e {
        case .preset(let p, let intensity):
            let name: JSONValue = .string(p.agentName)
            return intensity == Easing.standardIntensity ? name : ["preset": name, "intensity": number(intensity)]
        case .custom(let c): return [number(c.x1), number(c.y1), number(c.x2), number(c.y2)]
        }
    }
}

extension EffectKind {
    var agentName: String {
        switch self {
        case .dropShadow: return "dropShadow"
        case .innerShadow: return "innerShadow"
        case .layerBlur: return "layerBlur"
        case .backgroundBlur: return "backgroundBlur"
        case .glass: return "glass"
        }
    }
}

extension EasingPreset {
    /// The names the inspector shows, as an AI would say them.
    var agentName: String {
        switch self {
        case .none: return "linear"
        case .spring: return "elastic"
        default: return rawValue
        }
    }
}

/// Layers and actions as file JSON, changed by merge patches and read back
/// through the same checks a file from anywhere goes through.
enum ModelJSON {
    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue, what: String) throws -> T {
        let data = FileSafety.numbersHeld(try value.data())
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, context) {
            throw AgentError("\(what) is missing \(path(context.codingPath + [key]))")
        } catch let DecodingError.typeMismatch(_, context), let DecodingError.valueNotFound(_, context) {
            throw AgentError("\(what) has the wrong kind of value at \(path(context.codingPath)): \(context.debugDescription)")
        } catch let DecodingError.dataCorrupted(context) {
            throw AgentError("\(what) has a value Twine does not know at \(path(context.codingPath)): \(context.debugDescription)")
        } catch {
            throw AgentError("\(what) could not be read: \(error)")
        }
    }

    private static func path(_ keys: [CodingKey]) -> String {
        keys.isEmpty ? "the top" : keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    /// A layer changed by a merge patch. Its id never changes, new fills,
    /// strokes and effects get ids and defaults, and hex colours are taken
    /// where the file keeps `{r, g, b, a}`.
    static func patched(_ layer: Layer, with patch: JSONValue) throws -> Layer {
        guard case .object = patch else { throw AgentError("patch must be an object") }
        var json = try JSONValue.encoding(layer).merged(with: patch)
        json = filled(json)
        guard case .object(var o) = json else { throw AgentError("patch must be an object") }
        o["id"] = .string(layer.id.uuidString)
        let read = try decode(Layer.self, from: .object(o), what: "The patched layer")
        return FileSafety.held([read])[0]
    }

    static func patched(_ action: Action, with patch: JSONValue) throws -> Action {
        guard case .object = patch else { throw AgentError("patch must be an object") }
        guard case .object(var o) = filled(try JSONValue.encoding(action).merged(with: patch)) else {
            throw AgentError("patch must be an object")
        }
        o["id"] = .string(action.id.uuidString)
        let read = try decode(Action.self, from: .object(o), what: "The patched action")
        return FileSafety.held([read])[0]
    }

    /// An action whose values (its kind's own settings, such as a Move's
    /// `mode` and `end`) are changed by a merge patch.
    static func withValues(_ action: Action, _ values: JSONValue) throws -> Action {
        let key = action.spec.kind.rawValue
        return try patched(action, with: ["spec": .object([key: values])])
    }

    /// Fills in what an AI leaves out of a new list item: ids and the
    /// switch, and a stroke's every setting, from Twine's own defaults;
    /// and reads `"#RRGGBB"` wherever a colour goes.
    static func filled(_ value: JSONValue, key: String? = nil) -> JSONValue {
        switch value {
        case .object(var o):
            for (k, v) in o { o[k] = filled(v, key: k) }
            return .object(o)
        case .array(let items) where ["fills", "strokes", "effects"].contains(key):
            return .array(items.map { item in
                guard case .object(var o) = filled(item) else { return item }
                if o["id"] == nil { o["id"] = .string(UUID().uuidString) }
                if o["isEnabled"] == nil { o["isEnabled"] = true }
                if key == "strokes", let standard = try? JSONValue.encoding(LayerFactory.lineStroke) {
                    return standard.merged(with: .object(o))
                }
                if key == "fills", o["paint"] == nil { o["paint"] = ["type": "solid", "color": colorJSON(LayerFactory.defaultFill)] }
                return .object(o)
            })
        case .array(let items):
            return .array(items.map { filled($0) })
        case .string(let s) where key.map(isColorKey) == true:
            return RGBA(typed: s).map(colorJSON) ?? value
        default:
            return value
        }
    }

    private static func isColorKey(_ key: String) -> Bool {
        key == "color" || key.hasSuffix("Color")
    }

    static func colorJSON(_ c: RGBA) -> JSONValue {
        ["r": .number(c.r), "g": .number(c.g), "b": .number(c.b), "a": .number(c.a)]
    }
}
