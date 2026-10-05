import AppKit
import MotionModel
import MotionEditing
import Theme

/// What the ⌘K card offers in a project: actions and presets for the
/// selection, the tools, the timeline's own commands, every menu command
/// that can run now, the project's layers and scenes by name, and what is
/// typed directly (a time to go to, a value for the selection).
extension EditorController {
    func searchSource() -> SearchSource {
        var sections: [SearchSection] = []
        let actions = actionItems()
        if !actions.isEmpty { sections.append(SearchSection(title: "Actions", items: actions)) }
        let presets = presetItems()
        if !presets.isEmpty { sections.append(SearchSection(title: "Presets", items: presets)) }
        sections.append(SearchSection(title: "Tools", items: toolItems()))
        let timeline = timelineItems()
        if !timeline.isEmpty { sections.append(SearchSection(title: "Timeline", items: timeline)) }
        sections += MainMenu.searchSections()
        let scenes = sceneItems()
        if !scenes.isEmpty { sections.append(SearchSection(title: "Scenes", items: scenes)) }
        sections.append(SearchSection(title: "Layers", items: layerItems()))
        return SearchSource(sections: sections, typed: { [weak self] in self?.typedItems($0) ?? [] },
                            recentsKey: "searchRecents.editor")
    }

    // MARK: Animating

    /// Every action the selection can take, added at the playhead as the
    /// New Action menu adds it. From Design, Animate comes up first.
    private func actionItems() -> [SearchItem] {
        availableActions.filter { $0 != .preset }.map { kind in
            SearchItem(id: "action.\(kind.rawValue)", title: kind.defaultName, kind: "Action", icon: kind.icon,
                       keywords: [kind.category.rawValue, "action"], run: { [weak self] in
                self?.setMode(.animate)
                self?.addAction(kind)
            })
        }
    }

    /// Every preset the selection can take, both ways of a pair by their
    /// own names (Fade In, Fade Out), so either goes on directly.
    private func presetItems() -> [SearchItem] {
        availablePresets.flatMap { preset -> [Preset] in
            guard !preset.isText, let other = preset.kind.reversed else { return [preset] }
            return [Presets.preset(preset.kind), Presets.preset(other)]
        }
        .map { preset in
            SearchItem(id: "preset.\(preset.id)", title: preset.name, kind: "Preset", icon: .preset,
                       keywords: [preset.group.title, "preset"], run: { [weak self] in
                self?.setMode(.animate)
                self?.addPreset(preset)
            })
        }
    }

    private func toolItems() -> [SearchItem] {
        Tool.allCases.map { tool in
            SearchItem(id: "tool.\(tool.rawValue)", title: tool.title, kind: "Tool", icon: tool.icon, shortcut: tool.key,
                       isOn: editor.tool == tool, keywords: ["tool"], run: { [weak self] in
                self?.editor.tool = tool
                if tool.isShape { self?.editor.lastShape = tool }
            })
        }
    }

    /// The timeline's right-click commands, in Animate where it shows.
    private func timelineItems() -> [SearchItem] {
        guard editor.mode == .animate else { return [] }
        var items: [SearchItem] = []
        func add(_ title: String, icon: Icon? = nil, isOn: Bool = false, keywords: [String] = [], _ run: @escaping (EditorController) -> Void) {
            items.append(SearchItem(id: "timeline.\(title)", title: title, kind: "Timeline", icon: icon, isOn: isOn,
                                    keywords: keywords + ["timeline"], run: { [weak self] in if let self { run(self) } }))
        }
        if !selectedActions.isEmpty { add("Group into Scene", icon: .group) { $0.groupSelectedActionsIntoScene() } }
        if selectionHasScenes { add("Ungroup Scene") { $0.ungroupSelectedScenes() } }
        if canSplitPresets { add("Split into Actions", icon: .preset) { $0.splitSelectedPresets() } }
        if !project.actions.isEmpty {
            add("Fold All Layers", icon: .chevronUp) { $0.editor.foldedLayers = Set($0.project.actions.map(\.targetLayerID)) }
        }
        if !editor.foldedLayers.isEmpty { add("Unfold All Layers", icon: .chevronDown) { $0.editor.foldedLayers = [] } }
        add("Show Only Selected Layers", isOn: editor.timelineOnlySelected) { $0.editor.timelineOnlySelected.toggle() }
        add("Show Times as Frames", isOn: editor.showsFrames, keywords: ["seconds"]) { $0.editor.showsFrames.toggle() }
        add("Show Sound at the Bottom", isOn: editor.soundAtBottom, keywords: ["audio"]) { $0.editor.soundAtBottom.toggle() }
        return items
    }

    // MARK: Finding

    /// Every layer by name, with the groups it is in, selected when chosen
    /// (the layers panel opens its groups to show it).
    private func layerItems() -> [SearchItem] {
        var items: [SearchItem] = []
        func walk(_ layers: [Layer], path: [String]) {
            // Front first, as the layers panel lists them.
            for layer in layers.reversed() {
                let id = layer.id
                items.append(SearchItem(id: "layer.\(id.uuidString)", title: layer.name, kind: "Layer",
                                        detail: path.isEmpty ? nil : path.joined(separator: " › "), icon: layer.icon,
                                        onlyWhenSearching: true, run: { [weak self] in
                    guard let self, project.layer(withID: id) != nil else { return }
                    editor.showLayers = true
                    select([id])
                }))
                if layer.isGroup { walk(layer.children, path: path + [layer.name]) }
            }
        }
        walk(project.layers, path: [])
        return items
    }

    /// Every timeline scene by name: chosen, its actions are picked and
    /// shown, in Animate.
    private func sceneItems() -> [SearchItem] {
        project.scenes.map { scene in
            let id = scene.id
            return SearchItem(id: "scene.\(id.uuidString)", title: scene.name, kind: "Scene", icon: .group,
                              onlyWhenSearching: true, run: { [weak self] in
                guard let self, let scene = project.scenes.first(where: { $0.id == id }) else { return }
                setMode(.animate)
                editor.foldedScenes.remove(id)
                selectActions(Set(scene.actionIDs))
                editor.reveal(project.actions.filter { scene.actionIDs.contains($0.id) })
            })
        }
    }

    // MARK: Typed values

    /// What the typed words ask for directly: a time or frame to go to, or a
    /// value for the selection (`opacity 50`, `w 400`, `length 6s`).
    private func typedItems(_ text: String) -> [SearchItem] {
        TypedEntry.parse(text, framesShown: editor.showsFrames).compactMap { entry in
            switch entry {
            case .time(let t):
                let time = min(max(t, 0), lastFrameTime)
                return SearchItem(id: "typed.time", title: "Go to \(TimeFormat.seconds(time))", kind: "Playhead", icon: .play,
                                  run: { [weak self] in self?.goTo(time) })
            case .frame(let n):
                let frame = min(max(n, 0), max(project.composition.frameCount - 1, 0))
                return SearchItem(id: "typed.frame", title: "Go to Frame \(frame)", kind: "Playhead", icon: .play,
                                  run: { [weak self] in self?.goTo(self?.frameRate.time(ofFrame: frame) ?? 0) })
            case .property(.duration, let v):
                guard v > 0 else { return nil }
                let length = max(frameRate.snapped(min(v, Composition.longest)), frameRate.frameDuration)
                return SearchItem(id: "typed.duration", title: "Set Scene Length to \(TimeFormat.seconds(length))",
                                  kind: "Value", icon: .play, run: { [weak self] in self?.setSceneLength(length) })
            case .property(let property, let v):
                let layers = typedTargets(property, v)
                guard !layers.isEmpty else { return nil }
                return SearchItem(id: "typed.\(property.rawValue)", title: "Set \(property.title) to \(Self.typedReading(property, v))",
                                  kind: "Value", detail: layers.count == 1 ? layers[0].name : "\(layers.count) layers",
                                  icon: Self.typedIcon(property), run: { [weak self] in self?.setTyped(property, v) })
            }
        }
    }

    private func goTo(_ time: Double) {
        setMode(.animate)
        glide(to: time)
    }

    private func setSceneLength(_ length: Double) {
        var composition = project.composition
        composition.duration = length
        perform(.setComposition(composition))
    }

    /// The selected layers, unlocked, that `property` can be set to `value` on.
    private func typedTargets(_ property: TypedProperty, _ value: Double) -> [Layer] {
        selectedLayers.filter { layer in
            if case .audio = layer.content { return false }
            if isLocked(layer.id) { return false }
            switch property {
            case .width: return value >= 0 && (!layer.isGroup || layer.isFrame)
            case .height: return value >= 0 && (!layer.isGroup || layer.isFrame) && !layer.isText
            case .opacity: return value >= 0 && value <= 100
            case .radius:
                if value < 0 { return false }
                if case .rectangle? = layer.shapeGeometry { return true }
                return false
            case .x, .y, .rotation, .scale, .duration: return true
            }
        }
    }

    /// Sets the selection's design value, as typing it in the inspector
    /// would, as one undo step. In Animate the animation follows, as it
    /// does a resize or turn on the canvas.
    private func setTyped(_ property: TypedProperty, _ v: Double) {
        let edited = typedTargets(property, v).map { layer -> Layer in
            var l = layer
            switch property {
            case .x: l.transform.position = Vec2(v, l.transform.position.y)
            case .y: l.transform.position = Vec2(l.transform.position.x, v)
            case .width: l = l.resized(toWidth: v)
            case .height: l = l.resized(toHeight: v)
            case .rotation: l.transform.rotation = v
            case .opacity: l.opacity = v / 100
            case .scale:
                let s = l.transform.scale
                l.transform.scale = Vec2(s.x < 0 ? -v / 100 : v / 100, s.y < 0 ? -v / 100 : v / 100)
            case .radius:
                if var look = l.look {
                    look.geometry = .rectangle(cornerRadii: CornerRadii(all: v))
                    l.look = look
                }
            case .duration: break
            }
            return l
        }
        guard !edited.isEmpty else { return NSSound.beep() }
        let change = editor.mode == .animate ? animatedUpdate(edited) : layerUpdate(edited)
        perform(.batch([change], name: "Set \(property.title)"))
    }

    /// The value as the inspector shows it, with its unit.
    private static func typedReading(_ property: TypedProperty, _ v: Double) -> String {
        let number = v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        switch property {
        case .opacity, .scale: return number + "%"
        case .rotation: return number + "°"
        case .duration: return number + "s"
        default: return number + " px"
        }
    }

    private static func typedIcon(_ property: TypedProperty) -> Icon {
        switch property {
        case .x, .y: .move
        case .width, .height: .resize
        case .rotation: .rotate
        case .opacity: .opacity
        case .scale: .scale
        case .radius: .corners
        case .duration: .play
        }
    }
}
