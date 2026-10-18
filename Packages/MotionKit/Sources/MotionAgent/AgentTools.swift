import Foundation

/// The tools' names, descriptions and arguments, as an AI app lists them.
extension TwineAgent {
    /// What the AI is told when it connects: how Twine thinks, in brief.
    public static let instructions = """
    Twine is a Mac motion design app. A project is a composition (size, length, frame rate, background) holding layers \
    (shapes, text, frames, groups, pictures, video, sound) and actions. Layers hold their design: how they look when \
    nothing moves them. Actions animate them: each changes one property of one layer from a start time over a duration \
    with an easing, picking up from wherever the property is at its start. There are no keyframes. Presets are \
    ready-made animations on one bar (Fade In, Slide Out, Letters Rise). Templates are frames of picture cards in 3D.

    Start with get_status and get_project (an outline with every id), and describe for the lists of actions, presets, \
    templates and easings with example values. Coordinates are pixels from the top-left, y down, rotation clockwise in \
    degrees, times in seconds. Every change is one undo step the person can undo with Command-Z, and shows in Twine at \
    once. Check your work with render_frame. To show animation, set_view to animate. Change only what you were asked to; \
    the person may be working in the same project.
    """

    public static let tools: [AgentTool] = [
        AgentTool("get_status", "What Twine is showing: the open project, its composition, the mode, the playhead and the selection.",
                  schema([:])),
        AgentTool("list_projects", "Every project in the Twine projects folder, newest first.", schema([:])),
        AgentTool("open_project", "Opens a project by its name (from list_projects) or its path, closing the one open after saving it.",
                  schema(["name": string("The project's name"), "path": string("The .twine package's path")])),
        AgentTool("new_project", "Makes a project in the projects folder and opens it, from Settings' size unless given, optionally from a template.",
                  schema(["name": string("Its name; Untitled when left out"), "width": number("Pixels"), "height": number("Pixels"),
                          "duration": number("Seconds"), "fps": number("Frames a second: 24, 25, 30, 50 or 60"),
                          "background": string("Hex colour"), "template": string("A template kind or name, from describe")])),
        AgentTool("get_project", """
            The open project. With no arguments, an outline: the composition, every layer (id, type, box, look, children, front first) \
            and every action (id, layer, kind, start, duration, easing, values). With layer_ids or action_ids, their exact file JSON, \
            which update_layers and update_actions patch. full: true gives the whole file.
            """,
                  schema(["layer_ids": ids("Layers to give whole, with their actions"), "action_ids": ids("Actions to give whole"),
                          "full": boolean("The whole project file; long")])),
        AgentTool("describe", "Twine's lists: layer JSON examples and notes, every action kind with example values, presets, templates with their settings, and easings.",
                  schema(["topic": enumeration(["layers", "actions", "presets", "templates", "easing", "everything"], "What to describe")])),
        AgentTool("add_layer", """
            Adds a layer in front (or at index, 0 being the back) of the composition or of parent_id's group or frame. x and y are \
            its top-left in the parent; left out, it is centred. Text sizes itself to its words unless given a width. patch is a \
            JSON merge patch over the new layer's file JSON for anything else (effects, gradients, strokes' settings).
            """,
                  schema(["type": enumeration(["rectangle", "ellipse", "polygon", "star", "line", "text", "frame", "group"], "What to add"),
                          "name": string("Its name"), "parent_id": string("A group or frame to put it in"),
                          "index": number("Its place among its siblings, 0 at the back"),
                          "x": number("Left edge"), "y": number("Top edge"), "width": number("Pixels"), "height": number("Pixels"),
                          "fill": string("Hex colour, or none"), "stroke": string("Hex colour, or none"), "stroke_width": number("Pixels"),
                          "corner_radius": number("Pixels"), "opacity": number("0 to 1"), "sides": number("A polygon's sides"),
                          "points": number("A star's points"), "text": string("A text's words; \\n starts a line"),
                          "font_family": string("Such as Inter or SF Pro"), "font_size": number("Points"),
                          "font_weight": number("100 to 900"), "color": string("A text's hex colour"),
                          "alignment": enumeration(["left", "center", "right"], "A text's alignment"),
                          "blend_mode": string("From describe(layers)"), "patch": object("A merge patch over the layer's file JSON")],
                         required: ["type"])),
        AgentTool("update_layers", """
            Changes layers, all as one undo step. Each update has the layer's id and any of the add_layer settings (x, y, width, \
            height, rotation, scale, opacity, name, fill, stroke, text, font settings, visible, locked), and patch, a JSON merge \
            patch over its file JSON (get_project with its id shows it). Moving a layer carries its Move actions along.
            """,
                  schema(["updates": array(object("{id, ...changes}"), "One per layer")], required: ["updates"])),
        AgentTool("delete", "Deletes layers (with their actions and children) and actions, as one undo step.",
                  schema(["layer_ids": ids("Layers"), "action_ids": ids("Actions")])),
        AgentTool("arrange_layers", """
            Groups, frames, ungroups, moves into another parent, restacks or masks layers, keeping them where they are on screen \
            and carrying their actions. group and frame need layers sharing a parent; use_as_mask makes the back one mask the rest.
            """,
                  schema(["operation": enumeration(["group", "frame", "ungroup", "move", "bring_forward", "send_backward",
                                                    "bring_to_front", "send_to_back", "use_as_mask", "remove_mask"], "What to do"),
                          "layer_ids": ids("The layers"), "parent_id": string("For move: the group or frame, or leave out for the top"),
                          "index": number("For move: the place among the new siblings, 0 at the back"),
                          "name": string("For group and frame")],
                         required: ["operation", "layer_ids"])),
        AgentTool("add_action", """
            Adds an action of one kind to each layer, at start (the playhead when left out), on new timeline rows. values is a \
            merge patch over the kind's own settings, as describe(actions) shows: for example kind move with \
            {"mode": "to", "end": {"x": 960, "y": 540}}, kind opacity with {"initial": 0, "end": 1}, kind scale with \
            {"mode": "to", "end": {"x": 1.2, "y": 1.2}}, kind rotate with {"mode": "by", "end": 360}.
            """,
                  schema(["layer_ids": ids("The layers to animate"), "kind": string("An action kind, from describe(actions)"),
                          "start": number("Seconds"), "duration": number("Seconds; 0 is instant"),
                          "easing": easingSchema, "values": object("The kind's settings to change"),
                          "name": string("The bar's name"), "motion_blur": number("Shutter as a share of a frame, 0.5 standard; 0 off"),
                          "patch": object("A merge patch over the whole action's file JSON")],
                         required: ["layer_ids", "kind"])),
        AgentTool("add_preset", "Adds a preset (Fade In, Slide Out, Letters Rise, Pulse...) to each layer as one bar at start, optionally with its settings changed.",
                  schema(["layer_ids": ids("The layers"), "preset": string("A preset's name or kind, from describe(presets)"),
                          "start": number("Seconds"), "duration": number("Seconds"), "easing": easingSchema,
                          "settings": object("A merge patch over the preset's settings, as default_settings in describe(presets)"),
                          "name": string("The bar's name")],
                         required: ["layer_ids", "preset"])),
        AgentTool("update_actions", "Changes actions, as one undo step: each update has the action's id and any of start, duration, easing, name, enabled, motion_blur, layer_id, values (over its kind's settings) and patch (over its whole file JSON).",
                  schema(["updates": array(object("{id, ...changes}"), "One per action")], required: ["updates"])),
        AgentTool("add_template", "Adds a template: a frame of picture cards in 3D filling the composition, with a bar that plays it. pictures fills its slots from files.",
                  schema(["template": string("A template kind or name, from describe(templates)"),
                          "pictures": array(string("A file path"), "Pictures or videos for its slots, in order"),
                          "settings": object("Settings by key, from describe(templates)")],
                         required: ["template"])),
        AgentTool("set_composition", "Changes the composition's size, length, frame rate or background.",
                  schema(["width": number("Pixels"), "height": number("Pixels"), "duration": number("Seconds"),
                          "fps": number("Frames a second"), "background": string("Hex colour"),
                          "transparent": boolean("Whether exports keep the background clear")])),
        AgentTool("set_view", "Changes what the person sees: Design or Animate, the playhead, and what is selected.",
                  schema(["mode": enumeration(["design", "animate"], "Design shows the layout; Animate the playhead's moment"),
                          "time": number("The playhead, in seconds"), "select_layers": ids("Layers to select; [] for none"),
                          "select_actions": ids("Actions to select on the timeline")])),
        AgentTool("undo", "Undoes the last steps, the person's or yours, as Command-Z does; redo: true redoes.",
                  schema(["redo": boolean("Redo instead"), "steps": number("How many, 1 when left out")])),
        AgentTool("render_frame", "Draws the composition as a picture: the design, or the moment at time. Use it to check your work.",
                  schema(["time": number("Seconds; the playhead in Animate when left out"), "design": boolean("The design, with no animation"),
                          "max_size": number("The longer side in pixels, 1024 when left out, at most 2048")])),
        AgentTool("import_media", "Brings files in as layers: pictures (as picture-filled rectangles), videos, sounds and SVGs (as editable layers).",
                  schema(["paths": array(string("A file path"), "The files"), "x": number("Centre"), "y": number("Centre")],
                         required: ["paths"])),
        AgentTool("export", "Exports the project and waits for the file. Movies take the whole timeline unless start and end are given; png is one frame, the design unless time is given.",
                  schema(["format": enumeration(["mp4", "hevc", "hevc-alpha", "prores", "prores4444", "gif", "webm", "png"], "The kind of file"),
                          "path": string("Where to write it; beside the export folder from Settings, or the project, when left out"),
                          "scale": number("1 is the composition's size"), "fps": number("Frames a second"),
                          "start": number("Seconds"), "end": number("Seconds"), "time": number("For png: the moment")])),
    ]

    // MARK: Schema pieces

    private static func schema(_ properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var o: [String: JSONValue] = ["type": "object", "properties": .object(properties)]
        if !required.isEmpty { o["required"] = .array(required.map { .string($0) }) }
        return .object(o)
    }

    private static func string(_ description: String) -> JSONValue { ["type": "string", "description": .string(description)] }
    private static func number(_ description: String) -> JSONValue { ["type": "number", "description": .string(description)] }
    private static func boolean(_ description: String) -> JSONValue { ["type": "boolean", "description": .string(description)] }
    private static func object(_ description: String) -> JSONValue { ["type": "object", "description": .string(description)] }
    private static func array(_ items: JSONValue, _ description: String) -> JSONValue {
        ["type": "array", "items": items, "description": .string(description)]
    }
    private static func ids(_ description: String) -> JSONValue { array(["type": "string"], description) }
    private static func enumeration(_ values: [String], _ description: String) -> JSONValue {
        ["type": "string", "enum": .array(values.map { .string($0) }), "description": .string(description)]
    }
    private static var easingSchema: JSONValue {
        ["description": "A name (smooth, natural, slowDown, accelerate, elastic, bounce, overshoot, impulse, swing, linear...), {preset, intensity}, or [x1, y1, x2, y2]"]
    }
}
