import Foundation
import MotionModel
import MotionEvaluation
import MotionEditing
import MotionExport

/// Twine's tools for AI apps (Claude, Cursor and anything else that speaks
/// the Model Context Protocol). Every change goes through `EditorCommand`
/// as one undo step, the same road the canvas and the inspector take, so
/// it shows at once and undoes with ⌘Z.
@MainActor
public final class TwineAgent {
    public let host: AgentHost

    public init(host: AgentHost) { self.host = host }

    /// A protocol server answering with these tools. It keeps them (and
    /// so the host) for as long as it lives.
    public func server(version: String) -> MCPServer {
        MCPServer(name: "twine", version: version, instructions: Self.instructions, tools: Self.tools) { name, arguments in
            await self.call(name, arguments)
        }
    }

    /// A server that knows the tools but has no project, for the bridge:
    /// it answers the handshake and the tool list, and hands tool calls on.
    public static func listing(version: String) -> MCPServer {
        MCPServer(name: "twine", version: version, instructions: instructions, tools: tools) { _, _ in
            .error("Tools are run by Twine itself.")
        }
    }

    public func call(_ name: String, _ arguments: JSONValue) async -> ToolOutput {
        do {
            return try await run(name, Arguments(arguments))
        } catch let error as AgentError {
            return .error(error.description)
        } catch let error as LocalizedError {
            return .error(error.errorDescription ?? "\(error)")
        } catch {
            return .error("\(error)")
        }
    }

    private func run(_ name: String, _ a: Arguments) async throws -> ToolOutput {
        switch name {
        case "get_status": return .json(status())
        case "list_projects": return .json(listProjects())
        case "open_project": return try await openProject(a)
        case "new_project": return try await newProject(a)
        case "get_project": return try getProject(a)
        case "describe": return try describe(a)
        case "add_layer": return try addLayer(a)
        case "update_layers": return try updateLayers(a)
        case "delete": return try delete(a)
        case "arrange_layers": return try arrange(a)
        case "add_action": return try addAction(a)
        case "add_preset": return try addPreset(a)
        case "update_actions": return try updateActions(a)
        case "add_template": return try await addTemplate(a)
        case "set_composition": return try setComposition(a)
        case "set_view": return try setView(a)
        case "undo": return try undo(a)
        case "render_frame": return try await render(a)
        case "import_media": return try await importMedia(a)
        case "export": return try await export(a)
        default: throw AgentError("There is no tool called \(name)")
        }
    }

    // MARK: Reading

    private func project() throws -> Project {
        guard let project = host.store?.project else {
            throw AgentError("No project is open in Twine. Use list_projects and open_project, or new_project.")
        }
        return project
    }

    private func perform(_ command: EditorCommand) throws {
        do {
            try host.perform(command)
        } catch let error as EditorError {
            switch error {
            case .notFound(let id): throw AgentError("Nothing in the project has the id \(id.uuidString)")
            case .duplicateID(let id): throw AgentError("The id \(id.uuidString) is already used")
            case .invalidMove: throw AgentError("A layer cannot go inside itself, and grouped layers must share a parent")
            case .invalidValue: throw AgentError("A value is out of range (times run from 0 to a day, sizes must be above 0)")
            }
        }
    }

    func status() -> JSONValue {
        var o: [String: JSONValue] = [
            "app": "Twine",
            "showing": .string(host.store == nil ? "home" : "project"),
        ]
        if let project = host.store?.project {
            o["project"] = .string(host.projectURL?.deletingPathExtension().lastPathComponent ?? "Untitled")
            if let url = host.projectURL { o["path"] = .string(url.path) }
            o["mode"] = .string(host.isAnimating ? "animate" : "design")
            o["playhead"] = ProjectOutline.number(host.playhead)
            o["composition"] = ProjectOutline.composition(project.composition)
            var count = 0
            project.forEachLayer { _ in count += 1 }
            o["layer_count"] = .number(Double(count))
            o["action_count"] = .number(Double(project.actions.count))
            o["selected_layers"] = .array(host.selectedLayers.sorted { $0.precedes($1) }.map { .string($0.uuidString) })
            o["selected_actions"] = .array(host.selectedActions.sorted { $0.precedes($1) }.map { .string($0.uuidString) })
            if let undo = host.store?.undoManager.undoActionName, host.store?.undoManager.canUndo == true {
                o["undo"] = .string(undo)
            }
        }
        return .object(o)
    }

    private func listProjects() -> JSONValue {
        let formatter = ISO8601DateFormatter()
        return ["projects": .array(host.projects().sorted { $0.modified > $1.modified }.map { p in
            var o: [String: JSONValue] = ["name": .string(p.name), "path": .string(p.url.path),
                                          "modified": .string(formatter.string(from: p.modified))]
            if let folder = p.folder { o["folder"] = .string(folder) }
            if p.url.resolvingSymlinksInPath() == host.projectURL?.resolvingSymlinksInPath() { o["open"] = true }
            return .object(o)
        })]
    }

    private func openProject(_ a: Arguments) async throws -> ToolOutput {
        let url: URL
        if let path = a.string("path") {
            url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard url.pathExtension == ProjectFormat.fileExtension, FileManager.default.fileExists(atPath: url.path) else {
                throw AgentError("There is no Twine project at \(path)")
            }
        } else if let name = a.string("name") {
            let all = host.projects()
            let wanted = name.lowercased()
            let found = all.first { $0.name.lowercased() == wanted }
                ?? all.filter { $0.name.lowercased().contains(wanted) }.max { $0.modified < $1.modified }
            guard let found else { throw AgentError("No project is called \(name). list_projects shows them all.") }
            url = found.url
        } else {
            throw AgentError("Give the project's name or path")
        }
        try await host.openProject(at: url)
        return .json(status())
    }

    private func newProject(_ a: Arguments) async throws -> ToolOutput {
        var composition = host.newComposition
        try setComposition(&composition, from: a)
        var made = Project(composition: composition)
        if let name = a.string("template") {
            let kind = try template(named: name)
            made = Templates.project(kind, composition: composition)
        }
        try await host.newProject(named: a.string("name"), project: made)
        return .json(status())
    }

    private func getProject(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        let layerIDs = try a.ids("layer_ids"), actionIDs = try a.ids("action_ids")
        if !layerIDs.isEmpty || !actionIDs.isEmpty {
            var layers: [JSONValue] = []
            for id in layerIDs {
                guard let layer = p.layer(withID: id) else { throw AgentError("No layer has the id \(id.uuidString)") }
                layers.append(try JSONValue.encoding(layer))
            }
            let wanted = Set(actionIDs), owners = Set(layerIDs)
            let actions = try p.actions.filter { wanted.contains($0.id) || owners.contains($0.targetLayerID) }
                .map { try JSONValue.encoding($0) }
            if let missing = wanted.first(where: { id in !p.actions.contains { $0.id == id } }) {
                throw AgentError("No action has the id \(missing.uuidString)")
            }
            return .json(["layers": .array(layers), "actions": .array(actions)])
        }
        if try a.bool("full") == true {
            return .json(try JSONValue.encoding(p))
        }
        return .json(ProjectOutline.project(p))
    }

    private func describe(_ a: Arguments) throws -> ToolOutput {
        let topic = a.string("topic")?.lowercased() ?? "everything"
        guard let value = AgentCatalog.describe(topic) else {
            throw AgentError("Topics are layers, actions, presets, templates, easing or everything")
        }
        return .json(value)
    }

    // MARK: Layers

    private func addLayer(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        guard let type = a.string("type")?.lowercased() else { throw AgentError("type is needed") }
        let parentID = try a.id("parent_id")
        let parentSize: Size2
        if let parentID {
            guard let parent = p.layer(withID: parentID), parent.isGroup else {
                throw AgentError("parent_id must be a group or frame")
            }
            parentSize = parent.size
        } else {
            parentSize = p.composition.size
        }
        let name = a.string("name")
        func box(_ w: Double, _ h: Double) throws -> Box {
            let width = try a.number("width") ?? w, height = try a.number("height") ?? h
            guard width >= 0, height >= 0 else { throw AgentError("width and height cannot be below 0") }
            let x = try a.number("x") ?? (parentSize.width - width) / 2
            let y = try a.number("y") ?? (parentSize.height - height) / 2
            return Box(origin: Vec2(x, y), size: Size2(width, height))
        }

        var layer: Layer
        switch type {
        case "rectangle", "ellipse", "polygon", "star", "line":
            let kind = LayerFactory.ShapeKind(rawValue: type)!
            layer = LayerFactory.shape(kind, in: try box(200, type == "line" ? 0 : 200),
                                       name: name ?? LayerFactory.nextName(kind.title, in: p))
            if case .shape(var shape) = layer.content {
                if let sides = try a.int("sides"), case .polygon(_, let r) = shape.geometry {
                    shape.geometry = .polygon(sides: FileSafety.corners(sides), cornerRadius: r)
                }
                if let points = try a.int("points"), case .star(_, let inner, let r) = shape.geometry {
                    shape.geometry = .star(points: FileSafety.corners(points), innerRadius: inner, cornerRadius: r)
                }
                layer.content = .shape(shape)
            }
        case "frame":
            layer = LayerFactory.frame(in: try box(400, 300), name: name ?? LayerFactory.nextName("Frame", in: p))
        case "group":
            layer = LayerFactory.group(in: try box(0, 0), children: [], name: name ?? LayerFactory.nextName("Group", in: p))
        case "text":
            let at = Vec2(try a.number("x") ?? 0, try a.number("y") ?? 0)
            layer = LayerFactory.text(at: at, name: name ?? "Text")
        default:
            throw AgentError("type must be rectangle, ellipse, polygon, star, line, text, frame or group")
        }
        let (styled, _) = try style(layer, a, in: p)
        layer = styled
        if layer.isText {
            if let w = try a.number("width") { layer = layer.resized(width: w) }
            if name == nil, case .text(let t) = layer.content {
                layer.name = String(t.text.split(separator: "\n").first ?? "Text").prefix(40).description
            }
            layer = layer.fittedText()
            // Placed by its top-left, or in the middle of its parent.
            let size = layer.size
            let want = Vec2(try a.number("x") ?? (parentSize.width - size.width) / 2,
                            try a.number("y") ?? (parentSize.height - size.height) / 2)
            layer = layer.translated(by: want - ProjectOutline.topLeft(of: layer))
        }
        if let patch = a["patch"] { layer = try ModelJSON.patched(layer, with: patch) }
        let index = try a.int("index")
        try perform(.batch([.insertLayers([layer], parentID: parentID, index: index)], name: "Add \(layer.name)"))
        let added = host.store?.project.layer(withID: layer.id) ?? layer
        return .json(["id": .string(layer.id.uuidString), "layer": ProjectOutline.layer(added)])
    }

    private func updateLayers(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        let updates = try a.objects("updates")
        guard !updates.isEmpty else { throw AgentError("updates is needed: a list of {id, ...changes}") }
        var working = p
        var commands: [EditorCommand] = []
        var changed: [UUID] = []
        for u in updates {
            let id = try u.requiredID("id")
            guard var layer = working.layer(withID: id) else { throw AgentError("No layer has the id \(id.uuidString)") }
            layer = try placed(layer, u)
            let (styled, moved) = try style(layer, u, in: working)
            layer = styled
            if let patch = u["patch"] { layer = try ModelJSON.patched(layer, with: patch) }
            var step = [working.updating([layer])]
            if !moved.isEmpty { step.append(.updateActions(moved)) }
            for command in step { try? command.apply(to: &working) }
            commands += step
            changed.append(id)
        }
        try perform(.batch(commands, name: changed.count == 1 ? "Edit Layer" : "Edit Layers"))
        let now = try project()
        return .json(["layers": .array(changed.compactMap { now.layer(withID: $0).map(ProjectOutline.layer) })])
    }

    /// Size, place, turn and scale, as the inspector's Position and Layout
    /// set them: the top-left stays put as the size changes.
    private func placed(_ layer: Layer, _ a: Arguments) throws -> Layer {
        var l = layer
        let w = try a.number("width"), h = try a.number("height")
        if w != nil || h != nil {
            if l.isGroup && !l.isFrame {
                throw AgentError("A group is the size of its children. Scale it instead (scale), or make it a frame.")
            }
            guard (w ?? 0) >= 0, (h ?? 0) >= 0 else { throw AgentError("width and height cannot be below 0") }
            l = l.resized(width: w, height: l.isText ? nil : h)
        }
        if let s = a["scale"] {
            if let n = s.number { l.transform.scale = Vec2(n, n) }
            else if let pair = s.array, pair.count == 2, let x = pair[0].number, let y = pair[1].number {
                l.transform.scale = Vec2(x, y)
                l.transform.isScaleLinked = x == y
            } else { throw AgentError("scale is a number or [x, y], 1 being 100%") }
        }
        if let r = try a.number("rotation") { l.transform.rotation = r }
        if let z = try a.number("z") { l.transform.z = z }
        let x = try a.number("x"), y = try a.number("y")
        if x != nil || y != nil {
            let corner = ProjectOutline.topLeft(of: l)
            l = l.translated(by: Vec2((x ?? corner.x) - corner.x, (y ?? corner.y) - corner.y))
        }
        return l
    }

    /// Everything but the box: name, look, text and switches. Returns the
    /// Path actions a corner radius carried along.
    private func style(_ layer: Layer, _ a: Arguments, in p: Project) throws -> (Layer, [Action]) {
        var l = layer
        // A new layer is named as it is made; this renames one.
        if a.has("id"), let name = a.string("name"), !name.trimmingCharacters(in: .whitespaces).isEmpty { l.name = name }
        if let o = try a.number("opacity") { l.opacity = min(max(o > 1 ? o / 100 : o, 0), 1) }
        if let v = try a.bool("visible") { l.isVisible = v }
        if let v = try a.bool("locked") { l.isLocked = v }
        if let mode = a.string("blend_mode") {
            guard let blend = BlendMode(rawValue: mode) else {
                throw AgentError("blend_mode is one of \(BlendMode.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            l.blendMode = blend
        }

        if case .text(var t) = l.content {
            if let text = a.string("text") { t.text = text }
            if let family = a.string("font_family") { t.fontFamily = family }
            if let size = try a.number("font_size") { t.fontSize = min(max(size, 1), FileSafety.fontSizes.upperBound) }
            if let weight = try a.int("font_weight") { t.fontWeight = min(max(weight, 100), 900) }
            if let color = try a.color("color") ?? (a.string("fill") == "none" ? nil : a.color("fill")) { t.color = color }
            if a.string("fill") == "none" { t.hidesFill = true }
            if let align = a.string("alignment") {
                guard let alignment = TextAlignment(rawValue: align == "centre" ? "center" : align) else {
                    throw AgentError("alignment is left, center or right")
                }
                t.alignment = alignment
            }
            if let spacing = try a.number("letter_spacing") { t.letterSpacing = spacing }
            if let height = try a.number("line_height") { t.lineHeight = height }
            l.content = .text(t)
            return (l.fittedText(), [])
        }

        if var look = l.look {
            if a.string("fill")?.lowercased() == "none" {
                look.fills = []
            } else if let color = try a.color("fill") {
                if let top = look.topFillIndex, !look.fills[top].paint.isImage {
                    look.fills[top].paint = .solid(color)
                    look.fills[top].isEnabled = true
                } else {
                    look.fills.append(Fill(paint: .solid(color)))
                }
            }
            if a.string("stroke")?.lowercased() == "none" {
                look.strokes = []
            } else {
                let color = try a.color("stroke"), width = try a.number("stroke_width")
                if color != nil || width != nil {
                    if look.strokes.isEmpty {
                        var stroke = LayerFactory.lineStroke
                        stroke.width = 1
                        look.strokes.append(stroke)
                    }
                    if let color { look.strokes[0].paint = .solid(color) }
                    if let width { look.strokes[0].width = max(width, 0) }
                }
            }
            l.look = look
        }
        if let radius = try a.number("corner_radius") {
            guard l.look != nil else { throw AgentError("Only shapes and frames have corners to round") }
            if case .group(var g) = l.content, var frame = g.frame {
                frame.cornerRadii = CornerRadii(all: max(radius, 0))
                g.frame = frame
                l.content = .group(g)
            } else {
                let (rounded, moved) = CornerEditing.setting(radius, at: nil, of: l, actions: p.actions)
                return (rounded, moved)
            }
        }
        return (l, [])
    }

    private func delete(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        let layers = try a.ids("layer_ids"), actions = try a.ids("action_ids")
        guard !layers.isEmpty || !actions.isEmpty else { throw AgentError("Give layer_ids or action_ids") }
        for id in layers where p.layer(withID: id) == nil { throw AgentError("No layer has the id \(id.uuidString)") }
        for id in actions where !p.actions.contains(where: { $0.id == id }) {
            throw AgentError("No action has the id \(id.uuidString)")
        }
        var commands: [EditorCommand] = []
        if !actions.isEmpty { commands.append(.deleteActions(Set(actions))) }
        if !layers.isEmpty { commands.append(.deleteLayers(Set(layers))) }
        try perform(.batch(commands, name: layers.isEmpty ? "Delete Actions" : "Delete"))
        host.selectedLayers.subtract(layers)
        host.selectedActions.subtract(actions)
        return .json(["deleted_layers": .number(Double(layers.count)), "deleted_actions": .number(Double(actions.count))])
    }

    private func arrange(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        guard let operation = a.string("operation") else { throw AgentError("operation is needed") }
        let ids = try a.ids("layer_ids")
        guard !ids.isEmpty else { throw AgentError("layer_ids is needed") }
        for id in ids where p.layer(withID: id) == nil { throw AgentError("No layer has the id \(id.uuidString)") }
        var result: [String: JSONValue] = [:]
        switch operation {
        case "group", "frame":
            let asFrame = operation == "frame"
            let name = a.string("name") ?? LayerFactory.nextName(asFrame ? "Frame" : "Group", in: p)
            let (command, id) = try Arrangement.group(ids, in: p, name: name, asFrame: asFrame)
            try perform(command)
            result["id"] = .string(id.uuidString)
        case "ungroup":
            var working = p, commands: [EditorCommand] = [], freed: [UUID] = []
            for id in ids {
                guard working.layer(withID: id)?.isGroup == true else { throw AgentError("\(id.uuidString) is not a group or frame") }
                let (command, children) = try Arrangement.ungroup(id, in: working)
                try command.apply(to: &working)
                commands.append(command)
                freed += children
            }
            try perform(.batch(commands, name: "Ungroup"))
            result["layer_ids"] = .array(freed.map { .string($0.uuidString) })
        case "move":
            let parentID = try a.id("parent_id")
            if let parentID, p.layer(withID: parentID)?.isGroup != true { throw AgentError("parent_id must be a group or frame") }
            try perform(Arrangement.move(ids, to: parentID, index: try a.int("index"), in: p))
        case "bring_forward", "send_backward", "bring_to_front", "send_to_back":
            let direction: Arrangement.Direction = switch operation {
            case "bring_forward": .forward
            case "send_backward": .backward
            case "bring_to_front": .front
            default: .back
            }
            guard let command = Arrangement.restack(ids, direction, in: p) else { throw AgentError("Those layers do not share a parent") }
            try perform(command)
        case "use_as_mask":
            do {
                try perform(try Masking.useAsMask(ids, in: p))
            } catch let refusal as Masking.Refusal {
                switch refusal {
                case .apart: throw AgentError("Layers made into a mask must share a parent")
                case .cannotMask: throw AgentError("A group or a sound cannot be a mask")
                }
            }
        case "remove_mask":
            var working = p, commands: [EditorCommand] = []
            for id in ids {
                let command = try Masking.removeMask(id, in: working)
                try command.apply(to: &working)
                commands.append(command)
            }
            try perform(.batch(commands, name: "Remove Mask"))
        default:
            throw AgentError("operation is group, frame, ungroup, move, bring_forward, send_backward, bring_to_front, send_to_back, use_as_mask or remove_mask")
        }
        result["layers"] = ProjectOutline.project(try project())["layers"]
        return .json(.object(result))
    }

    // MARK: Actions

    private func layers(_ a: Arguments, in p: Project) throws -> [Layer] {
        let ids = try a.ids("layer_ids") + (try a.id("layer_id").map { [$0] } ?? [])
        guard !ids.isEmpty else { throw AgentError("layer_ids is needed") }
        return try ids.map { id in
            guard let layer = p.layer(withID: id) else { throw AgentError("No layer has the id \(id.uuidString)") }
            return layer
        }
    }

    private func easing(_ a: Arguments, key: String = "easing") throws -> Easing? {
        guard let value = a[key] else { return nil }
        return try Self.easing(value)
    }

    static func easing(_ value: JSONValue) throws -> Easing {
        func preset(_ name: String) throws -> EasingPreset {
            let key = name.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            let known: [String: EasingPreset] = ["linear": .none, "none": .none, "elastic": .spring, "spring": .spring]
            if let p = known[key] { return p }
            if let p = EasingPreset.allCases.first(where: { $0.rawValue.lowercased() == key }) { return p }
            throw AgentError("easing is one of \(EasingPreset.allCases.map(\.agentName).joined(separator: ", ")), or [x1, y1, x2, y2]")
        }
        switch value {
        case .string(let s): return .preset(try preset(s), intensity: Easing.standardIntensity)
        case .array(let n) where n.count == 4:
            let v = n.compactMap(\.number)
            guard v.count == 4, v.allSatisfy(\.isFinite) else { throw AgentError("a custom easing is four numbers") }
            return .custom(CubicBezier(min(max(v[0], 0), 1), v[1], min(max(v[2], 0), 1), v[3]))
        case .object(let o):
            guard let name = o["preset"]?.string else { throw AgentError("easing needs a preset") }
            let intensity = o["intensity"]?.number ?? Easing.standardIntensity
            return .preset(try preset(name), intensity: min(max(intensity, 0), 1))
        default: throw AgentError("easing is a name such as smooth, or [x1, y1, x2, y2]")
        }
    }

    private func timing(_ a: Arguments, rate: FrameRate) throws -> (start: Double, duration: Double?) {
        let start = try a.number("start") ?? host.playhead
        guard start >= 0, start <= Composition.longest else { throw AgentError("start runs from 0") }
        let duration = try a.number("duration")
        if let duration, duration < 0 || duration > Composition.longest { throw AgentError("duration cannot be below 0") }
        return (rate.snapped(start), duration.map(rate.snapped))
    }

    private func addAction(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        guard let name = a.string("kind"), let kind = ActionKind(rawValue: name) ?? ActionKind.allCases.first(where: {
            $0.defaultName.lowercased() == name.lowercased()
        }) else { throw AgentError("kind is needed; describe(topic: actions) lists them") }
        guard kind != .preset, kind != .template else { throw AgentError("Use add_preset or add_template for those") }
        let targets = try layers(a, in: p)
        let rate = p.composition.frameRate
        let (start, duration) = try timing(a, rate: rate)
        let easing = try easing(a) ?? host.newAction.easing
        let tracks = ActionTracks(p.actions)
        var made: [Action] = []
        for layer in targets {
            let offered = ActionFactory.kinds(for: layer, in: p)
            guard offered.contains(kind) else {
                throw AgentError("\(layer.name) cannot take \(kind.rawValue). It takes \(offered.map(\.rawValue).joined(separator: ", ")).")
            }
            let mediaLength = p.mediaLength(of: layer)
            var action = ActionFactory.make(kind, for: layer, at: start, state: tracks.state(of: layer, at: start),
                                            frameRate: rate, rowOrder: 0, mediaLength: mediaLength,
                                            duration: duration ?? host.newAction.duration, easing: easing)
            if kind == .dash, duration == nil {
                action.easing = .linear
                action.duration = max(rate.snapped(p.composition.duration - action.start), action.duration)
            }
            if let duration, action.duration != duration, kind != .visibility { action.duration = duration }
            action = try finished(action, a)
            made.append(action)
        }
        return try insert(made, name: made.first.map { "Add \($0.name)" } ?? "Add Action")
    }

    /// The action's name, values, blur and whole-action patch, as asked.
    private func finished(_ action: Action, _ a: Arguments) throws -> Action {
        var action = action
        if let values = a["values"] { action = try ModelJSON.withValues(action, values) }
        if let name = a.string("name") { action.name = name }
        if let blur = try a.number("motion_blur") { action.motionBlur = blur > 0 ? min(blur, 1) : nil }
        if let on = try a.bool("enabled") { action.isEnabled = on }
        if let patch = a["patch"] { action = try ModelJSON.patched(action, with: patch) }
        return action
    }

    private func insert(_ made: [Action], name: String) throws -> ToolOutput {
        let p = try project()
        let added = ActionEditing.appendingRows(made, in: p)
        guard !added.isEmpty else { throw AgentError("Nothing to add") }
        try perform(.batch([.insertActions(added)], name: name))
        return .json(["actions": .array(added.map(ProjectOutline.action))])
    }

    private func addPreset(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        guard let name = a.string("preset") else { throw AgentError("preset is needed; describe(topic: presets) lists them") }
        let preset = try Self.preset(named: name)
        let targets = try layers(a, in: p)
        let rate = p.composition.frameRate
        let (start, duration) = try timing(a, rate: rate)
        var made: [Action] = []
        for layer in targets {
            guard Presets.suits(preset, [layer], in: p) else {
                throw AgentError("\(preset.name) does not suit \(layer.name) (\(ProjectOutline.kind(of: layer)))")
            }
            var action = Presets.action(preset, for: layer, at: start, frameRate: rate)
            if let duration { action.duration = max(duration, rate.frameDuration) }
            if let easing = try easing(a) { action.easing = easing }
            if let settings = a["settings"] { action = try ModelJSON.withValues(action, settings) }
            action = try finished(action, a)
            made.append(action)
        }
        return try insert(made, name: preset.name)
    }

    /// A preset by its name as the picker shows it (Fade, Letters Rise), a
    /// direction's name (Fade Out) or its kind (`fade-out`).
    static func preset(named name: String) throws -> Preset {
        let wanted = name.lowercased().trimmingCharacters(in: .whitespaces)
        if let p = Presets.library.first(where: { $0.id == wanted || $0.name.lowercased() == wanted }) { return p }
        if let kind = PresetKind(rawValue: wanted) ?? PresetKind.allCases.first(where: { Presets.name(of: $0).lowercased() == wanted }) {
            return Presets.library.first { $0.kind == kind && !$0.isText } ?? Presets.preset(kind)
        }
        throw AgentError("No preset is called \(name); describe(topic: presets) lists them")
    }

    private func updateActions(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        let updates = try a.objects("updates")
        guard !updates.isEmpty else { throw AgentError("updates is needed: a list of {id, ...changes}") }
        let rate = p.composition.frameRate
        var edited: [Action] = []
        for u in updates {
            let id = try u.requiredID("id")
            guard var action = edited.first(where: { $0.id == id }) ?? p.actions.first(where: { $0.id == id }) else {
                throw AgentError("No action has the id \(id.uuidString)")
            }
            if let start = try u.number("start") {
                guard start >= 0 else { throw AgentError("start runs from 0") }
                action.start = rate.snapped(start)
            }
            if let duration = try u.number("duration") {
                guard duration >= 0 else { throw AgentError("duration cannot be below 0") }
                action.duration = rate.snapped(duration)
            }
            if let easing = try easing(u) { action.easing = easing }
            if let layer = try u.id("layer_id") {
                guard p.layer(withID: layer) != nil else { throw AgentError("No layer has the id \(layer.uuidString)") }
                action.targetLayerID = layer
            }
            action = try finished(action, u)
            edited.removeAll { $0.id == id }
            edited.append(action)
        }
        try perform(.batch([.updateActions(edited)], name: edited.count == 1 ? "Edit Action" : "Edit Actions"))
        return .json(["actions": .array(edited.map(ProjectOutline.action))])
    }

    // MARK: Templates

    func template(named name: String) throws -> TemplateKind {
        let wanted = name.lowercased()
        if let kind = TemplateKind(rawValue: wanted) { return kind }
        if let info = Templates.library.first(where: { $0.name.lowercased() == wanted }) { return info.kind }
        throw AgentError("No template is called \(name); describe(topic: templates) lists them")
    }

    private func addTemplate(_ a: Arguments) async throws -> ToolOutput {
        let p = try project()
        guard let name = a.string("template") else { throw AgentError("template is needed") }
        let kind = try template(named: name)
        var (command, frameID) = Templates.adding(kind, to: p)
        if let settings = a["settings"]?.object {
            var draft = p
            try command.apply(to: &draft)
            guard var frame = draft.layer(withID: frameID), var setup = frame.template else { throw AgentError("The template did not go in") }
            try Self.apply(settings, to: &setup)
            frame.template = setup
            command = .batch([command, .updateLayers([frame])], name: "Add Template")
        }
        try perform(command)
        let pictures = a.strings("pictures").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        if !pictures.isEmpty { try await host.fillTemplate(frameID, from: 0, with: pictures) }
        let frame = try project().layer(withID: frameID)
        return .json(["id": .string(frameID.uuidString), "layer": frame.map(ProjectOutline.layer) ?? .null,
                      "settings": AgentCatalog.templateControls(kind)])
    }

    /// Template settings by key: numbers for number settings, an option's
    /// key for a choice.
    static func apply(_ settings: [String: JSONValue], to setup: inout TemplateSetup) throws {
        let controls = TemplateRecipes.controls(setup.kind)
        for (key, value) in settings {
            switch key {
            case "corner_radius", "cornerRadius":
                guard let n = value.number else { throw AgentError("corner_radius is a share of the card's shorter side, 0 to 0.5") }
                setup.cornerRadius = min(max(n, 0), 0.5)
                continue
            case "shadow":
                guard let b = value.bool else { throw AgentError("shadow is true or false") }
                setup.shadow = b
                continue
            default: break
            }
            guard let control = controls.first(where: { $0.key == key }) else {
                throw AgentError("\(setup.kind.rawValue) has no setting \(key); it has \(controls.map(\.key).joined(separator: ", "))")
            }
            switch control.kind {
            case .number(let lo, let hi, _, _):
                guard let n = value.number else { throw AgentError("\(key) is a number from \(lo) to \(hi)") }
                setup.settings[key] = .number(min(max(n, lo), hi))
            case .choice(let options, _):
                guard let s = value.string, options.contains(where: { $0.key == s }) else {
                    throw AgentError("\(key) is one of \(options.map(\.key).joined(separator: ", "))")
                }
                setup.settings[key] = .choice(s)
            }
        }
    }

    // MARK: The composition and the view

    private func setComposition(_ c: inout Composition, from a: Arguments) throws {
        if let w = try a.int("width") { c.width = w }
        if let h = try a.int("height") { c.height = h }
        guard (1...16_384).contains(c.width), (1...16_384).contains(c.height) else {
            throw AgentError("width and height run from 1 to 16384")
        }
        if let d = try a.number("duration") {
            guard d > 0, d <= Composition.longest else { throw AgentError("duration must be above 0") }
            c.duration = d
        }
        if let fps = try a.number("fps") {
            guard let rate = FrameRate.presets.min(by: {
                abs(Double($0.frames) / Double($0.seconds) - fps) < abs(Double($1.frames) / Double($1.seconds) - fps)
            }), fps > 0 else { throw AgentError("fps must be above 0") }
            c.frameRate = rate
        }
        if let color = try a.color("background") { c.background.color = color }
        if let clear = try a.bool("transparent") { c.background.isTransparent = clear }
    }

    private func setComposition(_ a: Arguments) throws -> ToolOutput {
        var c = try project().composition
        try setComposition(&c, from: a)
        try perform(.setComposition(c))
        return .json(ProjectOutline.composition(c))
    }

    private func setView(_ a: Arguments) throws -> ToolOutput {
        let p = try project()
        if let mode = a.string("mode") {
            guard mode == "design" || mode == "animate" else { throw AgentError("mode is design or animate") }
            host.isAnimating = mode == "animate"
        }
        if let t = try a.number("time") {
            host.playhead = p.composition.frameRate.snapped(min(max(t, 0), p.composition.duration))
        }
        if a.has("select_layers") {
            let ids = try a.ids("select_layers")
            for id in ids where p.layer(withID: id) == nil { throw AgentError("No layer has the id \(id.uuidString)") }
            host.selectedLayers = Set(ids)
        }
        if a.has("select_actions") {
            let ids = try a.ids("select_actions")
            let actions = ids.compactMap { id in p.actions.first { $0.id == id } }
            guard actions.count == ids.count else { throw AgentError("Some of select_actions are not in the project") }
            // An action shows once its layer is picked too.
            host.selectedLayers.formUnion(actions.map(\.targetLayerID))
            host.selectedActions = Set(ids)
        }
        return .json(status())
    }

    private func undo(_ a: Arguments) throws -> ToolOutput {
        _ = try project()
        let redo = try a.bool("redo") ?? false
        let steps = min(max(try a.int("steps") ?? 1, 1), 50)
        var names: [JSONValue] = []
        for _ in 0..<steps {
            guard let name = host.undo(redo: redo) else { break }
            names.append(.string(name))
        }
        guard !names.isEmpty else { throw AgentError(redo ? "There is nothing to redo" : "There is nothing to undo") }
        return .json([redo ? "redone" : "undone": .array(names)])
    }

    // MARK: Pictures, files and export

    private func render(_ a: Arguments) async throws -> ToolOutput {
        let p = try project()
        let design = try a.bool("design")
        let time: Double? = design == true ? nil
            : try a.number("time").map { min(max($0, 0), p.composition.duration) } ?? (host.isAnimating || design == false ? host.playhead : nil)
        let side = min(max(try a.int("max_size") ?? 1024, 64), 2048)
        let png = try await host.render(at: time, maxSide: side)
        let caption = time.map { "The frame at \(ProjectOutline.number($0).text(pretty: false)) s" } ?? "The design"
        return ToolOutput([.text(caption), .png(png)])
    }

    private func importMedia(_ a: Arguments) async throws -> ToolOutput {
        _ = try project()
        let paths = a.strings("paths")
        guard !paths.isEmpty else { throw AgentError("paths is needed: files to bring in") }
        let urls = try paths.map { path -> URL in
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw AgentError("Twine cannot read \(path)") }
            return url
        }
        let x = try a.number("x"), y = try a.number("y")
        let center = x != nil || y != nil ? Vec2(x ?? 0, y ?? 0) : nil
        let ids = try await host.importFiles(urls, center: center)
        let p = try project()
        return .json(["layers": .array(ids.compactMap { p.layer(withID: $0).map(ProjectOutline.layer) })])
    }

    private func export(_ a: Arguments) async throws -> ToolOutput {
        let p = try project()
        let name = a.string("format")?.lowercased() ?? "mp4"
        let formats: [String: ExportFormat] = [
            "mp4": .h264, "h264": .h264, "hevc": .hevc, "hevc-alpha": .hevcAlpha, "hevcalpha": .hevcAlpha,
            "prores": .proRes422, "prores422": .proRes422, "prores4444": .proRes4444, "mov": .proRes422,
            "gif": .gif, "webm": .webm, "png": .png,
        ]
        guard let format = formats[name] else { throw AgentError("format is one of mp4, hevc, hevc-alpha, prores, prores4444, gif, webm or png") }
        let url = a.string("path").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        let start = try a.number("start"), end = try a.number("end")
        var range: ClosedRange<Double>?
        if start != nil || end != nil {
            let s = max(start ?? 0, 0), e = min(end ?? p.composition.duration, p.composition.duration)
            guard e > s else { throw AgentError("end must come after start") }
            range = s...e
        }
        let request = AgentExport(format: format, url: url, scale: min(max(try a.number("scale") ?? 1, 0.1), 4),
                                  frameRate: try a.int("fps"), range: range, time: try a.number("time"))
        let written = try await host.export(request)
        return .json(["path": .string(written.path)])
    }
}

extension Project {
    /// How long a video's or sound's file runs, for a new Play bar.
    func mediaLength(of layer: Layer) -> Double? {
        let id: UUID
        switch layer.content {
        case .video(let v): id = v.mediaID
        case .audio(let s): id = s.mediaID
        default: return nil
        }
        return media.first { $0.id == id }?.duration
    }
}
