import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering

/// Everything the editor can do to a project, in one place: the canvas, the
/// panels and the menus all call in here, and this is what turns their
/// gestures into commands. It holds no state of its own beyond what it is
/// handed; the project lives in the store and the view state in the model.
@MainActor
final class EditorController {
    let store: ProjectStore
    let editor: EditorModel
    weak var canvas: CanvasNSView?

    init(store: ProjectStore, editor: EditorModel) {
        self.store = store
        self.editor = editor
    }

    var project: Project { store.project }

    /// The scene at the playhead. Cheap enough to work out on demand.
    var scene: ResolvedScene { evaluate(store.project, at: editor.time) }

    // MARK: Selection

    /// The selection with anything that no longer exists left out, such as a
    /// layer an undo just took away.
    var selection: [UUID] {
        let all = project.allLayers.map(\.id)
        return all.filter(editor.selection.contains)
    }

    var selectedLayers: [Layer] { selection.compactMap(project.layer(withID:)) }

    func select(_ ids: [UUID], extending: Bool = false) {
        if extending {
            var next = editor.selection
            for id in ids {
                if next.contains(id) { next.remove(id) } else { next.insert(id) }
            }
            editor.selection = next
        } else {
            editor.selection = Set(ids)
        }
    }

    func selectAll() {
        editor.selection = Set(project.layers.filter { !$0.isLocked }.map(\.id))
    }

    func deselectAll() {
        editor.selection = []
    }

    /// Whether a layer or anything above it is locked, so it cannot be picked
    /// on the canvas.
    func isLocked(_ id: UUID) -> Bool {
        let chain = project.ancestors(of: id) + [id]
        return chain.contains { project.layer(withID: $0)?.isLocked == true }
    }

    // MARK: Running commands

    /// Runs a command as one undo step. A command that cannot apply beeps
    /// rather than failing silently.
    @discardableResult
    func perform(_ command: EditorCommand) -> Bool {
        do {
            try store.perform(command)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    /// Changes one layer through a copy of it, as one undo step.
    func edit(_ id: UUID, _ change: (inout Layer) -> Void) {
        guard var layer = project.layer(withID: id) else { return }
        change(&layer)
        perform(.updateLayers([layer]))
    }

    /// Changes every selected layer the same way, as one undo step.
    func editSelection(_ change: (inout Layer) -> Void) {
        let edited = selectedLayers.map { layer -> Layer in
            var l = layer
            change(&l)
            return l
        }
        guard !edited.isEmpty else { return }
        perform(.updateLayers(edited))
    }

    // MARK: Continuous changes (drags and sliders)

    func begin(_ name: String) { store.beginContinuousChange(name) }

    func update(_ layers: [Layer]) {
        try? store.updateContinuousChange(.updateLayers(layers))
    }

    func update(_ command: EditorCommand) {
        try? store.updateContinuousChange(command)
    }

    func end() { store.endContinuousChange() }

    func cancel() { store.cancelContinuousChange() }

    // MARK: How edits land

    /// Design mode shifts an animation, Animate mode keys at the playhead.
    var context: EditContext {
        EditContext(time: editor.time, mode: editor.mode == .animate ? .animate : .design,
                    frameDuration: project.composition.frameRate.frameDuration)
    }

    // MARK: Playback

    var duration: Double { project.composition.duration }
    var frameRate: FrameRate { project.composition.frameRate }
    /// The start of the last frame: the latest moment the playhead can show.
    var lastFrameTime: Double { frameRate.time(ofFrame: max(project.composition.frameCount - 1, 0)) }

    func togglePlay() {
        if !editor.isPlaying, editor.time >= lastFrameTime { editor.time = 0 }
        editor.isPlaying.toggle()
    }

    func stop() { editor.isPlaying = false }

    /// Moves the playhead, landing on a frame.
    func seek(to time: Double) {
        editor.time = min(max(frameRate.snapped(time), 0), lastFrameTime)
    }

    func step(_ frames: Int) {
        stop()
        seek(to: frameRate.time(ofFrame: frameRate.frame(at: editor.time) + frames))
    }

    func jumpToStart() { stop(); editor.time = 0 }
    func jumpToEnd() { stop(); editor.time = lastFrameTime }

    /// Called by the display's clock while playing. Plays in real time, and
    /// either loops or stops on the last frame.
    func advance(by seconds: Double) {
        guard editor.isPlaying else { return }
        var next = editor.time + seconds
        if next > lastFrameTime {
            if editor.loops && duration > 0 {
                next = next.truncatingRemainder(dividingBy: duration)
                if next > lastFrameTime { next = 0 }
            } else {
                next = lastFrameTime
                editor.isPlaying = false
            }
        }
        editor.time = next
    }

    // MARK: Keyframes

    /// Keyframes that still exist, for after an undo.
    var selectedKeyframes: Set<KeyframeRef> {
        editor.selectedKeyframes.filter { ref in
            guard let layer = project.layer(withID: ref.layerID),
                  let property = LayerProperties.get(ref.property, of: layer) else { return false }
            return property.marks.contains { $0.id == ref.keyframeID }
        }
    }

    func toggleStopwatch(_ property: PropertyID, on id: UUID) {
        guard let layer = project.layer(withID: id) else { return }
        let edited = Keyframing.toggleStopwatch(property, on: layer, at: editor.time)
        let on = LayerProperties.get(property, of: edited)?.isAnimated == true
        if perform(.batch([.updateLayers([edited])], name: on ? "Animate \(LayerProperties.title(property))"
                                                           : "Stop Animating \(LayerProperties.title(property))")), on {
            editor.timelineExpanded.insert(id)
        }
    }

    func toggleKeyframe(_ property: PropertyID, on id: UUID) {
        guard let layer = project.layer(withID: id) else { return }
        let edited = Keyframing.toggleKeyframe(property, on: layer, at: editor.time,
                                               tolerance: frameRate.frameDuration / 2)
        perform(.batch([.updateLayers([edited])], name: "Keyframe"))
    }

    func deleteSelectedKeyframes() {
        let refs = selectedKeyframes
        let layers = Set(refs.map(\.layerID)).compactMap(project.layer(withID:)).map { Keyframing.delete(refs, in: $0) }
        guard !layers.isEmpty else { return }
        if perform(.batch([.updateLayers(layers)], name: refs.count == 1 ? "Delete Keyframe" : "Delete Keyframes")) {
            editor.selectedKeyframes = []
        }
    }

    func setEasing(_ easing: Easing) {
        let refs = selectedKeyframes
        let layers = Set(refs.map(\.layerID)).compactMap(project.layer(withID:)).map { Keyframing.setEasing(easing, for: refs, in: $0) }
        guard !layers.isEmpty else { return }
        perform(.batch([.updateLayers(layers)], name: "Easing"))
    }

    /// For the easing editor's drags, which undo as one step.
    func updateEasing(_ easing: Easing) {
        let refs = selectedKeyframes
        update(Set(refs.map(\.layerID)).compactMap(project.layer(withID:)).map { Keyframing.setEasing(easing, for: refs, in: $0) })
    }

    static let keyframePasteboardType = NSPasteboard.PasteboardType("com.nidhin.emotion.keyframes")

    func copyKeyframes() {
        guard let clipboard = KeyframeClipboard.copy(selectedKeyframes, from: project),
              let data = try? JSONEncoder().encode(clipboard) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.keyframePasteboardType)
    }

    var canPasteKeyframes: Bool {
        NSPasteboard.general.data(forType: Self.keyframePasteboardType) != nil && !selection.isEmpty
    }

    /// Pastes onto each selected layer, the earliest keyframe at the playhead.
    func pasteKeyframes() {
        guard let data = NSPasteboard.general.data(forType: Self.keyframePasteboardType),
              let clipboard = try? JSONDecoder().decode(KeyframeClipboard.self, from: data) else { return }
        let layers = selectedLayers.map { clipboard.paste(onto: $0, at: editor.time) }
        guard !layers.isEmpty else { return }
        perform(.batch([.updateLayers(layers)], name: "Paste Keyframes"))
        for layer in layers { editor.timelineExpanded.insert(layer.id) }
    }

    /// Copies the chosen keyframes to the playhead.
    func duplicateKeyframes() {
        let refs = selectedKeyframes
        guard let clipboard = KeyframeClipboard.copy(refs, from: project) else { return }
        let layers = Set(refs.map(\.layerID)).compactMap(project.layer(withID:)).map { clipboard.paste(onto: $0, at: editor.time) }
        perform(.batch([.updateLayers(layers)], name: "Duplicate Keyframes"))
    }

    // MARK: Making layers

    func makeShape(_ tool: Tool, from start: Vec2, to end: Vec2) -> Layer? {
        guard let kind = tool.shapeKind else { return nil }
        let name = LayerFactory.nextName(kind.title, in: project)
        let duration = project.composition.duration
        if kind == .line { return LayerFactory.line(from: start, to: end, name: name, duration: duration) }
        let box = Box(minX: min(start.x, end.x), minY: min(start.y, end.y),
                      maxX: max(start.x, end.x), maxY: max(start.y, end.y))
        return LayerFactory.shape(kind, in: box, name: name, duration: duration)
    }

    // MARK: Arranging

    func deleteSelection() {
        if editor.focus == .timeline, !selectedKeyframes.isEmpty { return deleteSelectedKeyframes() }
        let ids = selection
        guard !ids.isEmpty else { return }
        perform(.deleteLayers(Set(ids)))
        editor.selection = []
    }

    func duplicateSelection() {
        if editor.focus == .timeline, !selectedKeyframes.isEmpty { return duplicateKeyframes() }
        let layers = topmost(selectedLayers)
        guard !layers.isEmpty else { return }
        // Duplicates land just in front of their originals, nudged so they
        // can be seen, the way Figma and Flip do it.
        var commands: [EditorCommand] = []
        var copies: [UUID] = []
        for layer in layers {
            guard let location = project.location(of: layer.id) else { continue }
            var copy = layer.duplicated().translated(by: Vec2(10, 10))
            copy.name = layer.name
            commands.append(.insertLayers([copy], parentID: location.parentID, index: location.index + 1))
            copies.append(copy.id)
        }
        if perform(.batch(commands, name: layers.count == 1 ? "Duplicate Layer" : "Duplicate Layers")) {
            editor.selection = Set(copies)
        }
    }

    func groupSelection() {
        let ids = topmost(selectedLayers).map(\.id)
        guard !ids.isEmpty else { return }
        do {
            let (command, groupID) = try Arrangement.group(ids, in: project, at: editor.time,
                                                           name: LayerFactory.nextName("Group", in: project))
            if perform(command) { editor.selection = [groupID] }
        } catch {
            NSSound.beep()
        }
    }

    func ungroupSelection() {
        let groups = selectedLayers.filter(\.isGroup)
        guard !groups.isEmpty else { return NSSound.beep() }
        var commands: [EditorCommand] = []
        var freed: [UUID] = []
        // One at a time against the project as each ungroup leaves it, so two
        // selected groups do not work from stale positions.
        var working = project
        for group in groups {
            guard let (command, children) = try? Arrangement.ungroup(group.id, in: working, at: editor.time) else { continue }
            try? command.apply(to: &working)
            commands.append(command)
            freed += children
        }
        if perform(.batch(commands, name: "Ungroup")) { editor.selection = Set(freed) }
    }

    func restack(_ direction: Arrangement.Direction) {
        let ids = selection
        guard let command = Arrangement.restack(ids, direction, in: project) else { return NSSound.beep() }
        perform(command)
    }

    /// Nudges the selection by `delta` in composition space.
    func nudge(by delta: Vec2) {
        let scene = self.scene
        let context = self.context
        let moved = topmost(selectedLayers).filter { !isLocked($0.id) }.map { layer in
            layer.moved(by: parentDelta(delta, for: layer.id, in: scene), in: context)
        }
        guard !moved.isEmpty else { return }
        perform(.updateLayers(moved))
    }

    /// A composition-space movement expressed in a layer's parent's space,
    /// which is what its position is measured in.
    func parentDelta(_ delta: Vec2, for id: UUID, in scene: ResolvedScene) -> Vec2 {
        guard let parent = project.location(of: id)?.parentID,
              let inverse = scene.worldTransform(of: parent)?.inverted else { return delta }
        return inverse.applyToVector(delta)
    }

    /// Of a set of layers, the ones not inside another one of the set.
    func topmost(_ layers: [Layer]) -> [Layer] {
        let ids = Set(layers.map(\.id))
        return layers.filter { Set(project.ancestors(of: $0.id)).isDisjoint(with: ids) }
    }

    // MARK: Clipboard

    static let pasteboardType = NSPasteboard.PasteboardType("com.nidhin.emotion.layers")

    func copySelection() {
        if editor.focus == .timeline, !selectedKeyframes.isEmpty { return copyKeyframes() }
        let layers = topmost(selectedLayers)
        guard !layers.isEmpty, let data = try? JSONEncoder().encode(layers) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.pasteboardType)
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    var canPaste: Bool {
        if editor.focus == .timeline, canPasteKeyframes { return true }
        return NSPasteboard.general.data(forType: Self.pasteboardType) != nil
    }

    /// Pastes in place, in front of everything at the top level. Every pasted
    /// layer is a new layer with new ids, however many times it is pasted.
    func paste() {
        if editor.focus == .timeline, canPasteKeyframes { return pasteKeyframes() }
        guard let data = NSPasteboard.general.data(forType: Self.pasteboardType),
              let layers = try? JSONDecoder().decode([Layer].self, from: data) else { return }
        let copies = layers.map { $0.duplicated() }
        if perform(.batch([.insertLayers(copies, parentID: nil, index: nil)],
                          name: copies.count == 1 ? "Paste Layer" : "Paste Layers")) {
            editor.selection = Set(copies.map(\.id))
        }
    }
}

extension Tool {
    var shapeKind: LayerFactory.ShapeKind? {
        switch self {
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .line: return .line
        case .polygon: return .polygon
        case .star: return .star
        default: return nil
        }
    }
}
