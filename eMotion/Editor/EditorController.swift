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
    /// The document, for reading and storing imported files.
    weak var document: ProjectDocument?
    /// Pictures and video frames for the canvas.
    private(set) lazy var media = MediaLibrary { [weak self] id in self?.document?.mediaURL(for: id) }
    /// Sounds' loudness, for the timeline's Play bars.
    let waveforms = Waveforms()
    /// The sound while playing.
    private lazy var audio = AudioPreview { [weak self] id in self?.document?.mediaURL(for: id) }

    private func followAudio() {
        audio.follow(project, time: editor.time, playing: editor.isPlaying)
    }

    /// The imported file a layer shows or plays, if it has one.
    func asset(ofLayer id: UUID) -> MediaAsset? {
        let mediaID: UUID
        switch project.layer(withID: id)?.content {
        case .image(let c): mediaID = c.mediaID
        case .video(let c): mediaID = c.mediaID
        case .audio(let c): mediaID = c.mediaID
        default: return nil
        }
        return project.media.first { $0.id == mediaID }
    }

    init(store: ProjectStore, editor: EditorModel) {
        self.store = store
        self.editor = editor
    }

    var project: Project { store.project }

    /// What the canvas shows: the design in Design mode, the moment at the
    /// playhead in Animate mode. Cheap enough to work out on demand.
    var scene: ResolvedScene {
        editor.mode == .animate ? evaluate(store.project, at: editor.time) : evaluateDesign(store.project)
    }

    // MARK: Modes

    /// Design builds the layout and shows it with no animation; Animate adds
    /// actions and shows the playhead's moment. Nothing carries across:
    /// playback stops on the way into Design, and the drawing tools put
    /// themselves away on the way into Animate.
    func setMode(_ mode: EditorModel.Mode) {
        guard editor.mode != mode else { return }
        if mode == .design {
            stop()
            // The timeline goes away, so the keyboard's edits go back to layers.
            editor.focus = .canvas
        } else {
            editor.tool = .select
        }
        editor.mode = mode
    }

    func toggleMode() {
        setMode(editor.mode == .design ? .animate : .design)
    }

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
        // Actions on layers no longer selected are let go of, so they do not
        // come back selected the next time their layer is picked.
        let selectedLayers = editor.selection
        let keep = project.actions.filter { editor.selectedActions.contains($0.id) && selectedLayers.contains($0.targetLayerID) }
        editor.selectedActions = Set(keep.map(\.id))
    }

    func selectAll() {
        editor.selection = Set(project.layers.filter { !$0.isLocked }.map(\.id))
    }

    func deselectAll() {
        editor.selection = []
        editor.selectedActions = []
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
        perform(layerUpdate([layer]))
    }

    /// Layer edits as one command. A layer whose design position moved
    /// takes its Move actions' absolute positions (To ends, initial values)
    /// with it, so its whole animation travels with it in either mode.
    func layerUpdate(_ layers: [Layer]) -> EditorCommand {
        var carried: [Action] = []
        for layer in layers {
            guard let old = project.layer(withID: layer.id) else { continue }
            let delta = layer.transform.position - old.transform.position
            guard delta != .zero else { continue }
            carried += project.actions(on: layer.id).filter { $0.spec.kind == .move }
                .map { $0.remapped(point: { $0 + delta }, vector: { $0 }) }
        }
        return carried.isEmpty ? .updateLayers(layers) : .batch([.updateLayers(layers), .updateActions(carried)], name: "Edit Layer")
    }

    /// Changes every selected layer the same way, as one undo step.
    func editSelection(_ change: (inout Layer) -> Void) {
        let edited = selectedLayers.map { layer -> Layer in
            var l = layer
            change(&l)
            return l
        }
        guard !edited.isEmpty else { return }
        perform(layerUpdate(edited))
    }

    // MARK: Continuous changes (drags and sliders)

    func begin(_ name: String) { store.beginContinuousChange(name) }

    func update(_ layers: [Layer]) {
        try? store.updateContinuousChange(layerUpdate(layers))
    }

    func update(_ command: EditorCommand) {
        try? store.updateContinuousChange(command)
    }

    func end() { store.endContinuousChange() }

    func cancel() { store.cancelContinuousChange() }

    // MARK: Playback

    var duration: Double { project.composition.duration }
    var frameRate: FrameRate { project.composition.frameRate }
    /// The start of the last frame: the latest moment the playhead can show.
    var lastFrameTime: Double { frameRate.time(ofFrame: max(project.composition.frameCount - 1, 0)) }

    func togglePlay() {
        if !editor.isPlaying, editor.time >= lastFrameTime { editor.time = 0 }
        editor.isPlaying.toggle()
        followAudio()
    }

    func stop() {
        editor.isPlaying = false
        followAudio()
    }

    /// Moves the playhead, landing on a frame.
    func seek(to time: Double) {
        editor.time = min(max(frameRate.snapped(time), 0), lastFrameTime)
    }

    func step(_ frames: Int) {
        stop()
        seek(to: frameRate.time(ofFrame: frameRate.frame(at: editor.time) + frames))
    }

    /// Jumps the playhead to the next or previous start or end of any action.
    func jumpToEdge(forward: Bool) {
        stop()
        let target = forward ? ActionEditing.edge(after: editor.time, in: project)
                             : ActionEditing.edge(before: editor.time, in: project)
        if let target { seek(to: target) } else { NSSound.beep() }
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
        followAudio()
    }

    // MARK: Importing

    /// Imports pictures, video and sound as new layers, centred on `point`
    /// (the middle of the composition when nil), and selects them. A video
    /// or a sound gets a Play bar for its whole length, at the playhead in
    /// Animate and at the start in Design. A file already in the project is
    /// used again rather than stored twice. Files that are none of these, or
    /// will not open, are skipped with a beep.
    func importMedia(_ urls: [URL], at point: Vec2? = nil) {
        guard let document else { return }
        Task { @MainActor in
            var commands: [EditorCommand] = []
            var added: [UUID] = []
            var skipped = false
            let composition = project.composition
            let center = point ?? Vec2(Double(composition.width) / 2, Double(composition.height) / 2)
            var offset = 0.0
            var known = project.media
            // Play bars go at the bottom of the timeline, in import order.
            var nextRow = ActionFactory.nextRowOrder(in: project)
            for url in urls {
                guard var asset = await MediaImport.describe(url) else { skipped = true; continue }
                if let existing = known.first(where: { $0.contentHash == asset.contentHash }) {
                    asset = existing
                } else {
                    do { try await document.stage(url, as: asset.fileName) } catch { skipped = true; continue }
                    commands.append(.addMedia(asset))
                    known.append(asset)
                }
                let name = url.deletingPathExtension().lastPathComponent
                let layer = LayerFactory.media(asset, center: Vec2(center.x + offset, center.y + offset),
                                               fitting: composition.size, name: name)
                offset += 20
                commands.append(.insertLayers([layer], parentID: nil, index: nil))
                if asset.kind != .image {
                    let start = editor.mode == .animate ? frameRate.snapped(editor.time) : 0
                    let play = Action(target: layer.id, start: start,
                                      duration: max(frameRate.snapped(asset.duration ?? 1), frameRate.frameDuration),
                                      name: "Play", rowOrder: nextRow, spec: .play(PlayAction()))
                    nextRow += 1
                    commands.append(.insertActions([play]))
                }
                added.append(layer.id)
            }
            if skipped { NSSound.beep() }
            guard !commands.isEmpty, perform(.batch(commands, name: added.count == 1 ? "Import" : "Import Files")) else { return }
            select(added)
        }
    }

    // MARK: Actions

    /// Kinds of action the selection can take together.
    var availableActions: [ActionKind] { ActionFactory.kinds(for: selectedLayers) }

    /// Adds an action of `kind` to every selected layer, at the playhead, on
    /// new rows at the bottom of the timeline, and selects them.
    func addAction(_ kind: ActionKind) {
        let tracks = ActionTracks(project.actions)
        let made = selectedLayers.filter { ActionFactory.kinds(for: $0).contains(kind) }.map { layer in
            ActionFactory.make(kind, for: layer, at: editor.time, state: tracks.state(of: layer, at: editor.time),
                               frameRate: frameRate, rowOrder: 0, mediaLength: asset(ofLayer: layer.id)?.duration)
        }
        let added = ActionEditing.appendingRows(made, in: project)
        guard let first = added.first else { return NSSound.beep() }
        if perform(.batch([.insertActions(added)], name: "Add \(first.name)")) { selectActions(Set(added.map(\.id))) }
    }

    // MARK: Action selection

    /// Selected actions that still exist and whose layers are still selected:
    /// picking another layer on the canvas lets go of the others' actions.
    var selectedActions: [Action] {
        project.actions.filter { editor.selectedActions.contains($0.id) && editor.selection.contains($0.targetLayerID) }
    }

    /// Picks actions, and their layers with them.
    func selectActions(_ ids: Set<UUID>) {
        editor.selectedActions = ids
        let targets = project.actions.filter { ids.contains($0.id) }.map(\.targetLayerID)
        if !targets.isEmpty { editor.selection = Set(targets) }
    }

    func deselectActions() { editor.selectedActions = [] }

    /// Delete, Duplicate and Copy act on actions after a click in the
    /// timeline, which only exists in Animate.
    var timelineHasFocus: Bool { editor.mode == .animate && editor.focus == .timeline }

    // MARK: Editing actions

    /// What an action picks up from when it has no initial value: its layer
    /// at the action's start, with the earlier actions on its channel.
    func inheritedState(for action: Action) -> LayerState? {
        guard let layer = project.layer(withID: action.targetLayerID) else { return nil }
        return ActionTracks(project.actions).inheritedState(for: action, of: layer)
    }

    /// Changes every selected action the same way, as one undo step.
    func editActions(_ name: String, _ change: (inout Action) -> Void) {
        let edited = selectedActions.map { action -> Action in
            var a = action
            change(&a)
            return a
        }
        guard !edited.isEmpty else { return }
        perform(.batch([.updateActions(edited)], name: name))
    }

    /// The same, as one step of a drag or a slider, between `begin` and `end`.
    func updateActions(_ change: (inout Action) -> Void) {
        let edited = selectedActions.map { action -> Action in
            var a = action
            change(&a)
            return a
        }
        guard !edited.isEmpty else { return }
        update(.updateActions(edited))
    }

    /// The one action the canvas edits: a single selected action, in
    /// Animate, whose layer is the only one selected.
    var canvasAction: Action? {
        let actions = selectedActions
        guard editor.mode == .animate, actions.count == 1, let action = actions.first,
              selection == [action.targetLayerID] else { return nil }
        return action
    }

    func deleteSelectedActions() {
        let ids = Set(selectedActions.map(\.id))
        guard !ids.isEmpty else { return }
        if perform(.deleteActions(ids)) { editor.selectedActions = [] }
    }

    /// Copies straight after the originals, selected.
    func duplicateSelectedActions() {
        let originals = selectedActions
        guard !originals.isEmpty else { return }
        let copies = ActionEditing.appendingRows(ActionEditing.duplicates(of: originals, rate: frameRate), in: project)
        if perform(.batch([.insertActions(copies)], name: copies.count == 1 ? "Duplicate Action" : "Duplicate Actions")) {
            selectActions(Set(copies.map(\.id)))
        }
    }

    /// Moves the selected actions by whole frames.
    func nudgeActions(frames: Int) {
        let moved = ActionEditing.moved(selectedActions, by: Double(frames) * frameRate.frameDuration, rate: frameRate)
        guard !moved.isEmpty else { return }
        perform(.batch([.updateActions(moved)], name: moved.count == 1 ? "Move Action" : "Move Actions"))
    }

    /// Switches actions on or off together: the one clicked, or the whole
    /// selection when the clicked one is part of it.
    func toggleEnabled(_ action: Action) {
        let group = editor.selectedActions.contains(action.id) ? selectedActions : [action]
        let on = !action.isEnabled
        let edited = group.map { a -> Action in
            var copy = a
            copy.isEnabled = on
            return copy
        }
        perform(.batch([.updateActions(edited)], name: on ? "Turn On Action" : "Turn Off Action"))
    }

    func renameAction(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var action = project.actions.first(where: { $0.id == id }), action.name != trimmed else { return }
        action.name = trimmed
        perform(.batch([.updateActions([action])], name: "Rename Action"))
    }

    /// Spaces the selected actions' starts `gap` seconds apart, in the order
    /// their rows run.
    func staggerSelectedActions(gap: Double) {
        let ordered = TimelineRow.order(of: selectedActions, in: project)
        guard ordered.count > 1 else { return NSSound.beep() }
        perform(.batch([.updateActions(ActionEditing.staggered(ordered, gap: gap, rate: frameRate))], name: "Stagger"))
    }

    static let actionPasteboardType = NSPasteboard.PasteboardType("com.nidhin.emotion.actions")
    static let easingPasteboardType = NSPasteboard.PasteboardType("com.nidhin.emotion.easing")

    /// Actions whose easing can be copied from or pasted onto: not instant,
    /// and not a Play, which runs at its clip's speed.
    private var easedSelection: [Action] {
        selectedActions.filter { !$0.isInstant && $0.spec.kind != .play }
    }

    var canCopyEasing: Bool { !easedSelection.isEmpty }
    var canPasteEasing: Bool {
        !easedSelection.isEmpty && NSPasteboard.general.data(forType: Self.easingPasteboardType) != nil
    }

    /// Copies the easing of the first selected action, down the timeline.
    func copyEasing() {
        guard let first = TimelineRow.order(of: easedSelection, in: project).first,
              let data = try? JSONEncoder().encode(first.easing) else { return NSSound.beep() }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.easingPasteboardType)
    }

    /// Gives every selected action the copied easing, as one undo step.
    func pasteEasing() {
        guard let data = NSPasteboard.general.data(forType: Self.easingPasteboardType),
              let easing = try? JSONDecoder().decode(Easing.self, from: data), !easedSelection.isEmpty else { return NSSound.beep() }
        editActions("Paste Easing") { a in
            if !a.isInstant && a.spec.kind != .play { a.easing = easing }
        }
    }

    func copySelectedActions() {
        let actions = selectedActions
        guard !actions.isEmpty, let data = try? JSONEncoder().encode(ActionClipboard(actions: actions)) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.actionPasteboardType)
    }

    /// Pastes with the earliest at the playhead, onto the selected layers,
    /// or back onto the layers they came from when nothing is selected.
    func pasteActions() {
        guard let data = NSPasteboard.general.data(forType: Self.actionPasteboardType),
              let clipboard = try? JSONDecoder().decode(ActionClipboard.self, from: data) else { return }
        let pasted = ActionEditing.appendingRows(
            ActionEditing.pasted(clipboard.actions, onto: selectedLayers, at: editor.time, in: project, rate: frameRate),
            in: project)
        guard !pasted.isEmpty else { return NSSound.beep() }
        if perform(.batch([.insertActions(pasted)], name: pasted.count == 1 ? "Paste Action" : "Paste Actions")) {
            selectActions(Set(pasted.map(\.id)))
        }
    }

    // MARK: Scene length

    func setDuration(_ seconds: Double) {
        var composition = project.composition
        composition.duration = max(frameRate.snapped(seconds), frameRate.frameDuration)
        update(.setComposition(composition))
    }

    // MARK: Making layers

    /// A new text layer with its top-left at `point`, selected. Dark on a
    /// light background, light on dark.
    @discardableResult
    func addText(at point: Vec2) -> UUID? {
        let background = project.composition.background
        let light = background.isTransparent || (background.color.r + background.color.g + background.color.b) / 3 > 0.5
        let layer = LayerFactory.text(at: point, name: LayerFactory.nextName("Text", in: project),
                                      color: light ? LayerFactory.defaultStroke : .white)
        guard perform(.insertLayers([layer], parentID: nil, index: nil)) else { return nil }
        select([layer.id])
        return layer.id
    }

    func makeShape(_ tool: Tool, from start: Vec2, to end: Vec2) -> Layer? {
        guard let kind = tool.shapeKind else { return nil }
        let name = LayerFactory.nextName(kind.title, in: project)
        if kind == .line { return LayerFactory.line(from: start, to: end, name: name) }
        let box = Box(minX: min(start.x, end.x), minY: min(start.y, end.y),
                      maxX: max(start.x, end.x), maxY: max(start.y, end.y))
        return LayerFactory.shape(kind, in: box, name: name)
    }

    // MARK: Arranging

    func deleteSelection() {
        // After a click in the timeline, Delete is for actions only; with
        // none selected it does nothing rather than reaching for the layer.
        if timelineHasFocus { return deleteSelectedActions() }
        let ids = selection
        guard !ids.isEmpty else { return }
        perform(.deleteLayers(Set(ids)))
        editor.selection = []
    }

    func duplicateSelection() {
        if timelineHasFocus, !selectedActions.isEmpty { return duplicateSelectedActions() }
        let layers = topmost(selectedLayers)
        guard !layers.isEmpty else { return }
        // Duplicates land just in front of their originals, nudged so they
        // can be seen, the way Figma and Flip do it.
        var commands: [EditorCommand] = []
        var copies: [UUID] = []
        var map: [UUID: UUID] = [:]
        for layer in layers {
            guard let location = project.location(of: layer.id) else { continue }
            var copy = layer.duplicated(recordingIDs: &map).translated(by: Vec2(10, 10))
            copy.name = layer.name
            commands.append(.insertLayers([copy], parentID: location.parentID, index: location.index + 1))
            copies.append(copy.id)
        }
        // Their animation comes too, nudged with them where it is absolute.
        let actions = project.actionCopies(for: map).map { $0.remapped(point: { $0 + Vec2(10, 10) }, vector: { $0 }) }
        if !actions.isEmpty { commands.append(.insertActions(actions)) }
        if perform(.batch(commands, name: layers.count == 1 ? "Duplicate Layer" : "Duplicate Layers")) {
            editor.selection = Set(copies)
        }
    }

    func groupSelection() {
        let ids = topmost(selectedLayers).map(\.id)
        guard !ids.isEmpty else { return }
        do {
            let (command, groupID) = try Arrangement.group(ids, in: project,
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
            guard let (command, children) = try? Arrangement.ungroup(group.id, in: working) else { continue }
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

    /// Nudges the selection's design position by `delta` in composition
    /// space.
    func nudge(by delta: Vec2) {
        let scene = self.scene
        let moved = topmost(selectedLayers).filter { !isLocked($0.id) }.map { layer in
            layer.translated(by: parentDelta(delta, for: layer.id, in: scene))
        }
        guard !moved.isEmpty else { return }
        perform(layerUpdate(moved))
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

    /// What goes on the pasteboard: the layers and the actions on them and
    /// on everything inside them.
    private struct LayerClipboard: Codable {
        var layers: [Layer]
        var actions: [Action]
    }

    func copySelection() {
        if timelineHasFocus, !selectedActions.isEmpty { return copySelectedActions() }
        let layers = topmost(selectedLayers)
        let ids = Set(layers.flatMap { [$0] + Project(layers: [$0]).allLayers }.map(\.id))
        let clipboard = LayerClipboard(layers: layers, actions: project.actions.filter { ids.contains($0.targetLayerID) })
        guard !layers.isEmpty, let data = try? JSONEncoder().encode(clipboard) else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setData(data, forType: Self.pasteboardType)
    }

    func cutSelection() {
        copySelection()
        deleteSelection()
    }

    var canPaste: Bool {
        let board = NSPasteboard.general
        return board.data(forType: Self.pasteboardType) != nil || board.data(forType: Self.actionPasteboardType) != nil
    }

    /// Pastes in place, in front of everything at the top level. Every pasted
    /// layer is a new layer with new ids, however many times it is pasted.
    func paste() {
        // Copying clears the pasteboard, so it holds layers or actions, never both.
        if NSPasteboard.general.data(forType: Self.actionPasteboardType) != nil { return pasteActions() }
        guard let data = NSPasteboard.general.data(forType: Self.pasteboardType),
              let clipboard = try? JSONDecoder().decode(LayerClipboard.self, from: data) else { return }
        var map: [UUID: UUID] = [:]
        let copies = clipboard.layers.map { $0.duplicated(recordingIDs: &map) }
        let actions = Project(actions: clipboard.actions).actionCopies(for: map)
        if perform(.batch([.insertLayers(copies, parentID: nil, index: nil), .insertActions(actions)],
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
