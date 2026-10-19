import Foundation
import MotionModel
import MotionEvaluation
import MotionEditing

/// What Twine offers, worked out from the app's own lists so it can never
/// drift from them: every action with the values it starts with, every
/// preset and template with its settings, the easings and layer shapes.
enum AgentCatalog {
    static func describe(_ topic: String) -> JSONValue? {
        switch topic {
        case "layers": return ["layers": layers]
        case "actions": return ["actions": actions]
        case "presets": return ["presets": presets]
        case "templates": return ["templates": templates]
        case "easing", "easings": return ["easing": easing]
        case "everything", "all":
            return ["layers": layers, "actions": actions, "presets": presets, "templates": templates, "easing": easing]
        default: return nil
        }
    }

    // MARK: Layers

    /// A layer of each kind as the file keeps it, with what the numbers mean.
    static var layers: JSONValue {
        let box = Box(origin: Vec2(100, 100), size: Size2(200, 120))
        var rectangle = LayerFactory.shape(.rectangle, in: box, name: "Rectangle 1")
        rectangle.look?.strokes = [Stroke(paint: .solid(RGBA(hex: "1E1E1E")!), width: 2)]
        let text = LayerFactory.text(at: Vec2(100, 300), name: "Text")
        let frame = LayerFactory.frame(in: Box(origin: Vec2(400, 100), size: Size2(320, 240)), name: "Frame 1")
        return [
            "notes": .array([
                "Coordinates are pixels, origin top-left, y down. A layer's x and y in outlines are its box's top-left in its parent (the composition, or the group or frame holding it, whose own top-left is 0, 0).",
                "In file JSON, transform.position is where the anchor sits in the parent and transform.anchor is pixels from the layer's own top-left (new layers anchor at their middle). Rotation is degrees clockwise about the anchor. Scale 1 is 100%. Opacity runs 0 to 1. Colours are {r, g, b, a} from 0 to 1; patches may also give \"#RRGGBB\".",
                "Layers are stored back to front: the last child is in front. Outlines list them front first, as the layers panel does.",
                "Fills are a list drawn bottom first; the last is the top fill. A text's colour is content.text.color. A text box is always the size of its words; give it a width to wrap.",
                "A frame is a group with a look (fills, strokes, corner radii) that clips its children by default. A plain group has no size of its own.",
            ]),
            "types": ["rectangle", "ellipse", "polygon", "star", "line", "path", "text", "frame", "group", "picture", "video", "audio", "template"],
            "blend_modes": .array(BlendMode.allCases.map { .string($0.rawValue) }),
            "example_rectangle": (try? JSONValue.encoding(rectangle)) ?? .null,
            "example_text": (try? JSONValue.encoding(text)) ?? .null,
            "example_frame": (try? JSONValue.encoding(frame)) ?? .null,
            "example_drop_shadow_effect": (try? JSONValue.encoding(Effect(kind: .dropShadow(DropShadow(color: .black, offset: Vec2(0, 8), blur: 24, opacity: 0.3))))) ?? .null,
        ]
    }

    // MARK: Actions

    /// Sample layers, one of each thing that takes different actions.
    private static var samples: [(String, Layer)] {
        let box = Box(origin: Vec2(0, 0), size: Size2(200, 200))
        var rectangle = LayerFactory.shape(.rectangle, in: box, name: "Rectangle")
        var stroke = LayerFactory.lineStroke
        stroke.dashPattern = [10, 10]
        rectangle.look?.strokes = [stroke]
        var path = LayerFactory.shape(.rectangle, in: box, name: "Path")
        if var look = path.look, let points = PathEditing.path(of: path) {
            look.geometry = .path(points)
            path.look = look
        }
        var frame3D = LayerFactory.frame(in: box, name: "Frame")
        frame3D.space3D = Space3D()
        let template = Templates.frame(.ringStream, filling: Composition())
        return [
            ("rectangle", rectangle),
            ("ellipse", LayerFactory.shape(.ellipse, in: box, name: "Ellipse")),
            ("star", LayerFactory.shape(.star, in: box, name: "Star")),
            ("path", path),
            ("text", LayerFactory.text(at: .zero, name: "Text")),
            ("frame", frame3D),
            ("group", LayerFactory.group(in: box, children: [], name: "Group")),
            ("template", template),
            ("audio", Layer(name: "Sound", content: .audio(AudioContent(mediaID: UUID())), size: Size2(0, 0), position: .zero)),
            ("video", Layer(name: "Video", content: .video(VideoContent(mediaID: UUID())), size: Size2(320, 180), position: .zero)),
        ]
    }

    static var actions: JSONValue {
        let samples = Self.samples
        let notes: [JSONValue] = [
            "An action changes one property of one layer from its start, over its duration, with an easing. With no initial value it picks up from wherever the property is at its start, which is how actions chain.",
            "values is the action's own settings, as in each kind's example below. mode \"by\" adds to the value at the start (Scale By multiplies); \"to\" is an absolute end. initial, when given, is the value it starts from, and on the first action of a property it holds from 0 s (an entrance).",
            "A layer is shown until a visibility action hides it. On one property of one layer, actions take over from each other in start order.",
            "move: end is pixels (by) or the anchor's place in the parent (to). scale: 1 is 100%. rotate: degrees clockwise. opacity: 0 to 1. resize: pixels. color: a paint. layerBlur: Figma's blur units.",
        ]
        var list: [JSONValue] = []
        for kind in ActionKind.allCases where kind != .preset && kind != .template {
            let takers = samples.filter { ActionFactory.kinds(for: $0.1, hasSound: true).contains(kind) }
            guard let sample = takers.first?.1 else { continue }
            let action = ActionFactory.make(kind, for: sample, at: 0, state: LayerState(design: sample),
                                            frameRate: .fps60, rowOrder: 0, mediaLength: 5)
            var o: [String: JSONValue] = [
                "kind": .string(kind.rawValue), "name": .string(kind.defaultName),
                "category": .string(kind.category.rawValue),
                "layers": .array(takers.map { .string($0.0) }),
            ]
            if kind != .path, let values = (try? JSONValue.encoding(action.spec))?[kind.rawValue] {
                o["example_values"] = values
            }
            list.append(.object(o))
        }
        return ["notes": .array(notes), "kinds": .array(list)]
    }

    // MARK: Presets

    static var presets: JSONValue {
        let notes: [JSONValue] = [
            "A preset is one bar doing several things at once (an entrance, an exit or an emphasis). Pairs go In and Out: name either way, such as \"Fade In\" or \"Fade Out\", or give the kind.",
            "settings change the preset's own values, as in each one's default_settings. unit (letters, words or lines), order and delay move a text's letters one by one.",
        ]
        let list: [JSONValue] = Presets.library.map { preset in
            var o: [String: JSONValue] = [
                "name": .string(preset.name), "group": .string(preset.group.rawValue),
                "kind": .string(preset.kind.rawValue),
            ]
            if let out = preset.kind.reversed { o["out_kind"] = .string(out.rawValue) }
            if preset.isText { o["text_only"] = true; o["id"] = .string(preset.id) }
            if preset.isSound { o["sound_only"] = true }
            let controls = Presets.controls(for: preset.kind)
            if !controls.isEmpty { o["settings"] = .array(controls.map { .string("\($0)") }) }
            o["default_settings"] = (try? JSONValue.encoding(preset.text ?? PresetRecipe.defaults(preset.kind))) ?? .null
            return .object(o)
        }
        return ["notes": .array(notes), "presets": .array(list)]
    }

    // MARK: Templates

    static var templates: JSONValue {
        let notes: [JSONValue] = [
            "A template is a frame of picture cards moving in 3D, filling the composition, with a bar that loops it. Give it pictures (file paths) to fill its slots; empty slots show samples. Its slots are its child layers, slot 1 the last child: a picture layer, a video layer, or an empty one named Empty slot. They are never drawn themselves; the cards show them.",
            "settings are by key: numbers within their range, or an option's key for a choice. corner_radius (a share of the card's shorter side) and shadow (true or false) suit every template.",
        ]
        return ["notes": .array(notes), "templates": .array(Templates.library.map { info in
            ["kind": .string(info.kind.rawValue), "name": .string(info.name), "group": .string(info.group.rawValue)]
        }), "settings_of_each": .object(Dictionary(uniqueKeysWithValues: Templates.library.map {
            ($0.kind.rawValue, templateControls($0.kind))
        }))]
    }

    static func templateControls(_ kind: TemplateKind) -> JSONValue {
        .array(TemplateRecipes.controls(kind).map { control in
            var o: [String: JSONValue] = ["key": .string(control.key), "name": .string(control.name)]
            switch control.kind {
            case .number(let lo, let hi, let standard, _):
                o["min"] = .number(lo); o["max"] = .number(hi); o["default"] = .number(standard)
            case .choice(let options, let standard):
                o["options"] = .array(options.map { .string($0.key) }); o["default"] = .string(standard)
            }
            return .object(o)
        })
    }

    // MARK: Easing

    static var easing: JSONValue {
        [
            "presets": .array(EasingPreset.allCases.map { .string($0.agentName) }),
            "forms": .array([
                "a name, such as \"smooth\", at its standard strength",
                "{\"preset\": \"bounce\", \"intensity\": 0.7}: 0 is a straight line, 0.5 the designed curve, 1 twice as strong",
                "[x1, y1, x2, y2]: a custom cubic bezier, as CSS writes one",
            ]),
        ]
    }
}
