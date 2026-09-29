import AppKit
import UniformTypeIdentifiers
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering
import MotionImport

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

    /// Lets go of the pictures, videos and waveforms of files no layer uses
    /// any more, as after a delete, an undone import or a replace. They stay
    /// in the package, so an undo brings them back from there. Run when
    /// changes settle (`ProjectDocument`), not on every step.
    func releaseUnusedMedia() {
        let used = Set(project.allLayers.flatMap(\.mediaIDs))
        media.keep(only: used)
        waveforms.keep(only: used)
        Thumbnail.videos.keep(only: used)
    }
    /// The sound while playing.
    private lazy var audio = AudioPreview { [weak self] id in self?.document?.mediaURL(for: id) }

    private func followAudio() {
        audio.follow(project, time: editor.time, playing: editor.isPlaying)
    }

    /// The imported file a layer plays, if it has one: its video or its
    /// sound.
    func asset(ofLayer id: UUID) -> MediaAsset? {
        let mediaID: UUID
        switch project.layer(withID: id)?.content {
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
        guard !isClosed else { return false }
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

    /// Opens a change that takes ordinary edits as its steps, for a drag
    /// across a number field, whose every step is the field's usual commit.
    func beginScrub(_ name: String) { store.beginContinuousChange(name, folding: true) }

    /// What the inspector's number fields report their drags to.
    var scrubbing: Scrubbing { Scrubbing(begin: { [weak self] in self?.beginScrub($0) }, end: { [weak self] in self?.end() }) }

    func update(_ layers: [Layer]) {
        guard !isClosed else { return }
        try? store.updateContinuousChange(layerUpdate(layers))
    }

    func update(_ command: EditorCommand) {
        guard !isClosed else { return }
        try? store.updateContinuousChange(command)
    }

    func end() { store.endContinuousChange() }

    /// A step of typing on the canvas, joining the steps before it with the
    /// same `key` (see `ProjectStore.perform(_:joining:)`). A joined step
    /// records nothing, so it also tells the document it has something to
    /// save: otherwise quitting or a crash mid-sentence would find nothing
    /// edited and lose the words.
    func type(_ layers: [Layer], joining key: String) {
        guard !isClosed else { return }
        try? store.perform(.batch([layerUpdate(layers)], name: "Edit Text"), joining: key)
        document?.updateChangeCount(.changeDone)
    }

    /// Finishes what is half done on the canvas, typing above all, so it is
    /// an undo step in the project before the editor gives up the window.
    func finishEditing() {
        canvas?.endTextEditing()
        end()
    }

    /// Set once the project has closed: an import still under way when it
    /// closes finishes into nothing, rather than changing a project that
    /// is gone, whose next save could write over a fresh copy of it.
    private(set) var isClosed = false

    /// Closes the editor to changes, stopping conversions under way.
    func closeDown() {
        isClosed = true
        WebMConversion.stopAll()
    }

    func cancel() { store.cancelContinuousChange() }

    // MARK: Playback

    var duration: Double { project.composition.duration }
    var frameRate: FrameRate { project.composition.frameRate }
    /// The start of the last frame: the latest moment the playhead can show.
    var lastFrameTime: Double { frameRate.time(ofFrame: max(project.composition.frameCount - 1, 0)) }

    func togglePlay() {
        cancelGlide()
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
        cancelGlide()
        editor.time = min(max(frameRate.snapped(time), 0), lastFrameTime)
    }

    /// The playhead sliding to where a click landed, rather than jumping.
    private var glideTimer: Timer?
    static let glideLength = 0.22

    /// Moves the playhead to `time` over a moment, easing out, and lands on
    /// the frame. Any other seek, a scrub or playing takes over at once.
    func glide(to time: Double, over length: Double = EditorController.glideLength, eased: Bool = true) {
        cancelGlide()
        let target = min(max(frameRate.snapped(time), 0), lastFrameTime)
        let from = editor.time
        guard abs(target - from) > 1e-9 else { return }
        let began = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = min((CACurrentMediaTime() - began) / max(length, 0.01), 1)
                let progress = eased ? 1 - pow(1 - t, 3) : t
                self.editor.time = t >= 1 ? target : from + (target - from) * progress
                if t >= 1 { self.cancelGlide() }
            }
        }
        // Also while the mouse is down, so it runs during a click's tracking.
        RunLoop.main.add(timer, forMode: .common)
        glideTimer = timer
    }

    private func cancelGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
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
        // SVG files are drawings to take apart, not pictures.
        let drawings = urls.filter { $0.pathExtension.lowercased() == "svg" }
        let urls = urls.filter { $0.pathExtension.lowercased() != "svg" }
        for (i, url) in drawings.enumerated() { importSVG(url, at: point.map { Vec2($0.x + Double(i) * 20, $0.y + Double(i) * 20) }) }
        guard !urls.isEmpty else { return }
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
                let asset: MediaAsset
                if WebMConversion.isWebM(url) {
                    guard let brought = await bringInWebM(url, known: known) else { continue }
                    asset = brought.asset
                    if brought.isNew {
                        commands.append(.addMedia(asset))
                        known.append(asset)
                    }
                } else {
                    guard var described = await MediaImport.describe(url) else { skipped = true; continue }
                    if let existing = known.first(where: { $0.contentHash == described.contentHash }) {
                        described = existing
                    } else {
                        do { try await document.stage(url, as: described.fileName) } catch { skipped = true; continue }
                        commands.append(.addMedia(described))
                        known.append(described)
                    }
                    asset = described
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

    // MARK: Pictures and video

    /// Asks for one file of one of `types`, as a sheet on the window.
    private func chooseFile(_ types: [UTType], then use: @escaping (URL) -> Void) {
        guard let window = canvas?.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak panel] response in
            guard response == .OK, let url = panel?.url else { return }
            use(url)
        }
    }

    /// A file brought into the project, or the copy already there, with
    /// whether it is new to the project. Nil, with a beep, for a file of
    /// another kind than `kind` or one that will not open.
    private func bringIn(_ url: URL, as kind: MediaKind) async -> (asset: MediaAsset, isNew: Bool)? {
        if WebMConversion.isWebM(url) {
            guard kind == .video else { NSSound.beep(); return nil }
            return await bringInWebM(url, known: project.media)
        }
        guard let document, let described = await MediaImport.describe(url), described.kind == kind else {
            NSSound.beep()
            return nil
        }
        if let existing = project.media.first(where: { $0.contentHash == described.contentHash }) { return (existing, false) }
        do { try await document.stage(url, as: described.fileName) } catch {
            NSSound.beep()
            return nil
        }
        return (described, true)
    }

    /// A WebM made into a movie macOS can open (`WebMConversion`) and staged,
    /// or the one already in the project from the same file: it is known by
    /// the WebM's own fingerprint, so importing it again converts nothing.
    /// What goes wrong is said in a notice.
    private func bringInWebM(_ url: URL, known: [MediaAsset]) async -> (asset: MediaAsset, isNew: Bool)? {
        guard let document, let hash = await MediaImport.fingerprint(url) else { NSSound.beep(); return nil }
        if let existing = known.first(where: { $0.contentHash == hash }) { return (existing, false) }
        editor.showNotice("Converting \(url.lastPathComponent)…")
        do {
            let movie = try await WebMConversion.convert(url)
            defer { try? FileManager.default.removeItem(at: movie) }
            guard var asset = await MediaImport.describe(movie) else {
                editor.showNotice("\(url.lastPathComponent) was converted but couldn't be opened.")
                return nil
            }
            asset.originalName = url.lastPathComponent
            asset.contentHash = hash
            try await document.stage(movie, as: asset.fileName)
            editor.notice = nil
            return (asset, true)
        } catch {
            editor.showNotice(error.localizedDescription)
            return nil
        }
    }

    /// Swaps a picture's or a video's file for another chosen in a panel,
    /// keeping the layer, its box and every action on it.
    func replaceMedia(of id: UUID) {
        guard let layer = project.layer(withID: id) else { return }
        if case .video = layer.content {
            chooseFile([.movie]) { [weak self] url in self?.replaceMedia(of: id, with: url) }
        } else if layer.picture != nil {
            chooseFile([.image]) { [weak self] url in self?.replaceMedia(of: id, with: url) }
        }
    }

    func replaceMedia(of id: UUID, with url: URL) {
        guard let layer = project.layer(withID: id) else { return }
        let isVideo: Bool
        if case .video = layer.content { isVideo = true } else if layer.picture != nil { isVideo = false } else { return }
        let old = layer.mediaIDs.first.flatMap { m in project.media.first { $0.id == m } }
        Task { @MainActor in
            guard let (asset, isNew) = await bringIn(url, as: isVideo ? .video : .image),
                  let current = project.layer(withID: id) else { return }
            var commands: [EditorCommand] = isNew ? [.addMedia(asset)] : []
            if isVideo {
                let replaced = PictureEditing.replacingVideo(current, with: asset, old: old, actions: project.actions)
                commands.append(.updateLayers([replaced.layer]))
                if !replaced.actions.isEmpty { commands.append(.updateActions(replaced.actions)) }
            } else {
                commands.append(.updateLayers([PictureEditing.replacingPicture(current, with: asset, old: old)]))
            }
            perform(.batch(commands, name: isVideo ? "Replace Video" : "Replace Image"))
        }
    }

    /// Fills a shape's first fill with a picture chosen in a panel.
    func fillWithPicture(_ id: UUID) {
        chooseFile([.image]) { [weak self] url in self?.fillWithPicture(id, from: url) }
    }

    func fillWithPicture(_ id: UUID, from url: URL) {
        Task { @MainActor in
            guard let (asset, isNew) = await bringIn(url, as: .image),
                  var layer = project.layer(withID: id), var shape = layer.look else { return }
            let paint = Paint.image(ImagePaint(mediaID: asset.id))
            if let top = shape.topFillIndex { shape.fills[top].paint = paint } else { shape.fills = [Fill(paint: paint)] }
            layer.look = shape
            perform(.batch((isNew ? [.addMedia(asset)] : []) + [.updateLayers([layer])], name: "Image Fill"))
        }
    }

    /// Changes how a layer's picture fills it. Crop starts cropping on the
    /// canvas, with the picture where it was.
    func setPictureMode(_ id: UUID, _ mode: ImageScaleMode) {
        guard let layer = project.layer(withID: id), let picture = layer.picture else { return }
        if picture.paint.mode != mode {
            perform(.batch([.updateLayers([PictureEditing.settingMode(layer, to: mode, pictures: project.pictureSizes)])],
                           name: "Image \(mode.title)"))
        }
        if mode == .crop { canvas?.beginCropping(id) }
    }

    /// Turns a layer's picture a quarter clockwise.
    func turnPicture(_ id: UUID) {
        guard let layer = project.layer(withID: id), layer.picture != nil else { return }
        perform(.batch([.updateLayers([PictureEditing.turned(layer)])], name: "Turn Image"))
    }

    /// A layer's picture, or its video's first frame, for the inspector.
    func preview(of mediaID: UUID) -> CGImage? {
        guard let asset = project.media.first(where: { $0.id == mediaID }) else { return nil }
        return asset.kind == .video ? media.videoFrame(mediaID, at: 0) : media.image(mediaID)
    }

    /// An SVG file as editable layers in a frame, centred on `point` (or the
    /// composition), shrunk to fit the composition if it is larger. Its
    /// pictures, embedded or drawn from its text, come into the project too.
    /// One undo step.
    func importSVG(_ url: URL, at point: Vec2? = nil) {
        guard let document else { return }
        let composition = project.composition
        let center = point ?? Vec2(Double(composition.width) / 2, Double(composition.height) / 2)
        let name = url.deletingPathExtension().lastPathComponent
        let fitting = composition.size
        Task { @MainActor in
            // Read on a worker thread: a large drawing takes a while, and the
            // app should not freeze meanwhile.
            let reading = Task.detached(priority: .userInitiated) { () -> SVGImport.Result? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? SVGImport.read(data, name: name, center: center, fitting: fitting)
            }
            guard let read = await reading.value else { return NSSound.beep() }
            let result = read.reusing(project.media)
            var commands: [EditorCommand] = []
            for item in result.media {
                do { try await document.stage(item.data, as: item.asset.fileName) } catch { return NSSound.beep() }
                commands.append(.addMedia(item.asset))
            }
            commands.append(.insertLayers([result.layer], parentID: nil, index: nil))
            if perform(.batch(commands, name: "Import SVG")) { select([result.layer.id]) }
        }
    }

    /// Layers copied with the Twine plugin in Figma, at their exact size,
    /// centred in the composition, which is never resized to fit them (the
    /// user's choice: they size it themselves). Their pictures come too.
    /// One undo step. Fonts this Mac lacks are named in a notice; the text
    /// shows in a stand-in until they are installed.
    func pasteFromFigma(_ text: String) {
        guard let document else { return }
        Task { @MainActor in
            // Read on a worker thread, pictures and all, as an SVG is.
            guard let read = await Task.detached(priority: .userInitiated, operation: { try? FigmaImport.read(text) }).value
            else { return NSSound.beep() }
            var commands: [EditorCommand] = []
            // Whole pixels, so edges that were crisp in Figma stay so.
            let c = project.composition
            let offset = Vec2((Double(c.width) / 2 - read.bounds.center.x).rounded(),
                              (Double(c.height) / 2 - read.bounds.center.y).rounded())
            for item in read.media where !project.media.contains(where: { $0.contentHash == item.asset.contentHash }) {
                do { try await document.stage(item.data, as: item.asset.fileName) } catch { return NSSound.beep() }
                commands.append(.addMedia(item.asset))
            }
            let layers = read.layers.map { $0.translated(by: offset) }.map { reusingKnownPictures($0, from: read.media) }
            commands.append(.insertLayers(layers, parentID: nil, index: nil))
            guard perform(.batch(commands, name: "Paste from Figma")) else { return }
            select(layers.map(\.id))
            var notes: [String] = []
            if !read.missingFonts.isEmpty {
                let names = read.missingFonts.joined(separator: ", ")
                notes.append(read.missingFonts.count == 1 ? "\(names) isn't installed, so a stand-in font shows until it is."
                                                          : "\(names) aren't installed, so a stand-in font shows until they are.")
            }
            notes += read.warnings.prefix(2)
            if read.warnings.count > 2 { notes.append("And \(read.warnings.count - 2) more left out.") }
            if !notes.isEmpty { editor.showNotice(notes.joined(separator: " ")) }
        }
    }

    /// A pasted layer's pictures taken from the project where it already has
    /// the same file.
    private func reusingKnownPictures(_ layer: Layer, from media: [SVGImport.EmbeddedMedia]) -> Layer {
        var l = layer
        if var look = l.look {
            for i in look.fills.indices {
                guard case .image(var p) = look.fills[i].paint,
                      let hash = media.first(where: { $0.asset.id == p.mediaID })?.asset.contentHash,
                      let known = project.media.first(where: { $0.contentHash == hash }) else { continue }
                p.mediaID = known.id
                look.fills[i].paint = .image(p)
            }
            l.look = look
        }
        l.children = l.children.map { reusingKnownPictures($0, from: media) }
        return l
    }

    // MARK: Actions

    /// Kinds of action the selection can take together.
    var availableActions: [ActionKind] { ActionFactory.kinds(for: selectedLayers, in: project) }

    /// Adds an action of `kind` to every selected layer, at the playhead, on
    /// new rows at the bottom of the timeline, and selects them.
    func addAction(_ kind: ActionKind) {
        let tracks = ActionTracks(project.actions)
        let made = selectedLayers.filter { ActionFactory.kinds(for: $0, in: project).contains(kind) }.map { layer in
            ActionFactory.make(kind, for: layer, at: editor.time, state: tracks.state(of: layer, at: editor.time),
                               frameRate: frameRate, rowOrder: 0, mediaLength: asset(ofLayer: layer.id)?.duration)
        }
        insertAndShow(made, name: made.first.map { "Add \($0.name)" } ?? "Add Action")
    }

    var availablePresets: [Preset] { Presets.available(for: selectedLayers, in: project) }

    /// Applies a preset to every selected layer that can take it, at the
    /// playhead: one bar each, on new rows at the bottom, selected and
    /// played, as Add Action's are. Its settings are in the inspector.
    func addPreset(_ preset: Preset) {
        let layers = selectedLayers.filter { Presets.available(for: [$0], in: project).contains(preset) }
        let made = layers.map { Presets.action(preset, for: $0, at: editor.time, frameRate: frameRate) }
        insertAndShow(made, name: preset.name)
    }

    /// Whether any selected action is a preset bar Split into Actions can
    /// take apart: not one moving letters one by one, or clipping.
    var canSplitPresets: Bool {
        selectedActions.contains { if case .preset(let p) = $0.spec { return Presets.splits(p) } else { return false } }
    }

    /// Swaps each selected preset bar for the ordinary actions it is made of,
    /// playing the same, in one undo step, and selects them.
    func splitSelectedPresets() {
        let tracks = ActionTracks(project.actions)
        var removed: Set<UUID> = []
        var added: [Action] = []
        for action in selectedActions {
            guard let layer = project.layer(withID: action.targetLayerID),
                  let parts = Presets.split(action, of: layer, from: tracks.inheritedState(for: action, of: layer),
                                            frameRate: frameRate) else { continue }
            removed.insert(action.id)
            added += parts
        }
        guard !removed.isEmpty else { return NSSound.beep() }
        if perform(.batch([.deleteActions(removed), .insertActions(added)], name: "Split into Actions")) {
            selectActions(Set(added.map(\.id)))
        }
    }

    /// Puts new actions on rows at the bottom, selects them, brings their
    /// rows into view, and plays them: the playhead runs from their start to
    /// their end at real speed (a long run hurried to a second) and waits
    /// there, ready for the next to follow on.
    private func insertAndShow(_ made: [Action], name: String) {
        let added = ActionEditing.appendingRows(made, in: project)
        guard !added.isEmpty else { return NSSound.beep() }
        guard perform(.batch([.insertActions(added)], name: name)) else { return }
        selectActions(Set(added.map(\.id)))
        editor.revealActions = (Set(added.map(\.id)), editor.revealActions.request + 1)
        guard let last = added.max(by: { $0.end < $1.end }), last.end > editor.time else { return }
        stop()
        glide(to: last.end, over: min(last.end - editor.time, 1), eased: false)
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
        // Only this layer's actions matter, and the canvas asks on every redraw.
        return ActionTracks(project.actions.filter { $0.targetLayerID == layer.id }).inheritedState(for: action, of: layer)
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

    /// Swaps every selected action's From and To, so it plays backwards, as
    /// one undo step. An empty From is filled in with what it inherits.
    func swapActionEnds() {
        editActions("Swap From and To") { a in
            guard let state = inheritedState(for: a), let swapped = ActionGeometry.swappingEnds(a, from: state) else { return }
            a = swapped
        }
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
        // A sound or video goes with its last Play bar.
        if perform(MediaPlays.deleting(ids, in: project)) {
            editor.selectedActions = []
            editor.selection = editor.selection.filter { project.layer(withID: $0) != nil }
        }
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

    static let actionPasteboardType = NSPasteboard.PasteboardType("com.nidhin.twine.actions")
    static let easingPasteboardType = NSPasteboard.PasteboardType("com.nidhin.twine.easing")

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

    // MARK: Export

    /// Brings up the export panel over the window, with playback stopped.
    func openExport() {
        stop()
        editor.showExport = true
    }

    /// Puts the panel away, stopping an export still running.
    func closeExport() {
        editor.exportPlayer?.pause()
        if editor.exports.isExporting { editor.exports.cancel() }
        editor.exports.forgetCompleted()
        editor.showExport = false
    }

    // MARK: Making layers

    /// A new text layer with its top-left at `point`, selected. Dark on a
    /// light background, light on dark.
    @discardableResult
    /// A text layer at a composition point, inside `parentID` when given.
    func addText(at point: Vec2, in parentID: UUID? = nil) -> UUID? {
        // Dark on a light ground, light on a dark one: the frame it goes in,
        // when that has a colour, or the composition's background.
        let background = project.composition.background
        var ground: RGBA? = background.isTransparent ? nil : background.color
        if let parentID, case .solid(let c)? = project.layer(withID: parentID)?.look?.fills.last?.paint { ground = c }
        let light = ground.map { ($0.r + $0.g + $0.b) / 3 > 0.5 } ?? true
        let made = LayerFactory.text(at: point, name: LayerFactory.nextName("Text", in: project),
                                     color: light ? LayerFactory.defaultStroke : .white)
        let layer = Arrangement.placed(made, into: parentID, in: project)
        guard perform(.insertLayers([layer], parentID: parentID, index: nil)) else { return nil }
        select([layer.id])
        return layer.id
    }

    func makeShape(_ tool: Tool, from start: Vec2, to end: Vec2) -> Layer? {
        if tool == .frame {
            let box = Box(minX: min(start.x, end.x), minY: min(start.y, end.y),
                          maxX: max(start.x, end.x), maxY: max(start.y, end.y))
            return LayerFactory.frame(in: box, name: LayerFactory.nextName("Frame", in: project))
        }
        guard let kind = tool.shapeKind else { return nil }
        let name = LayerFactory.nextName(kind.title, in: project)
        if kind == .line { return LayerFactory.line(from: start, to: end, name: name) }
        let box = Box(minX: min(start.x, end.x), minY: min(start.y, end.y),
                      maxX: max(start.x, end.x), maxY: max(start.y, end.y))
        return LayerFactory.shape(kind, in: box, name: name)
    }

    /// Moving the layers a new frame lies around into it, worked out after
    /// `first` (the frame's own insertion, when it has not happened yet).
    /// Nil when it lies around nothing.
    func enclosing(_ frameID: UUID, after first: EditorCommand? = nil) -> EditorCommand? {
        var p = project
        if let first { try? first.apply(to: &p) }
        return Arrangement.adopt(Arrangement.enclosed(by: frameID, in: p), into: frameID, in: p)
    }

    /// Puts the selection in a new frame around it, as Figma's Frame
    /// Selection does.
    func frameSelection() {
        let ids = topmost(selectedLayers).map(\.id)
        guard !ids.isEmpty else { return NSSound.beep() }
        do {
            let (command, frameID) = try Arrangement.group(ids, in: project, name: LayerFactory.nextName("Frame", in: project),
                                                           asFrame: true)
            if perform(command) { editor.selection = [frameID] }
        } catch {
            NSSound.beep()
        }
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
        let (command, copies) = duplicates(of: layers, offset: Vec2(10, 10))
        if perform(.batch([command], name: layers.count == 1 ? "Duplicate Layer" : "Duplicate Layers")) {
            editor.selection = Set(copies.map(\.id))
        }
    }

    /// Copies of layers where they stand, for an Option-drag, made inside
    /// the continuous change the drag has begun and selected. The drag then
    /// moves them, so the whole thing undoes as one step.
    func duplicateForDrag(_ layers: [Layer]) -> [Layer] {
        let (command, copies) = duplicates(of: layers, offset: .zero)
        update(command)
        editor.selection = Set(copies.map(\.id))
        return copies.compactMap { project.layer(withID: $0.id) }
    }

    /// Copies of layers, each just in front of its original and moved by
    /// `offset`, with their animation (moved with them where it is absolute).
    private func duplicates(of layers: [Layer], offset: Vec2) -> (EditorCommand, [Layer]) {
        var placed: [(copy: Layer, parentID: UUID?, index: Int)] = []
        var map: [UUID: UUID] = [:]
        for layer in layers {
            guard let location = project.location(of: layer.id) else { continue }
            var copy = layer.duplicated(recordingIDs: &map).translated(by: offset)
            copy.name = layer.name
            placed.append((copy, location.parentID, location.index))
        }
        // Copied side by side, a layer and its mask each point at the
        // other's copy only once every copy has its id.
        let copies = placed.map { $0.copy.remappingMasks(map) }
        var commands: [EditorCommand] = zip(copies, placed).map { copy, p in
            .insertLayers([copy], parentID: p.parentID, index: p.index + 1)
        }
        let actions = project.actionCopies(for: map).map { $0.remapped(point: { $0 + offset }, vector: { $0 }) }
        if !actions.isEmpty { commands.append(.insertActions(actions)) }
        return (.batch(commands, name: "Duplicate"), copies)
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

    // MARK: Aligning

    /// What aligning and distributing act on: the selected layers not
    /// inside another selected one, and not locked. Design only: in Animate
    /// the canvas shows a moment, not the layout.
    private var arrangeable: [Layer] {
        editor.mode == .design ? topmost(selectedLayers).filter { !isLocked($0.id) } : []
    }

    var canAlign: Bool { !arrangeable.isEmpty }
    var canDistribute: Bool { arrangeable.count >= 3 }

    /// Lines the selected layers up on one edge or centre: one layer with
    /// the composition, several with the box around them all.
    func align(_ edge: Alignment.Edge) {
        let boxes = arrangeableBoxes()
        guard let first = boxes.values.first else { return }
        let reference = boxes.count == 1 ? Box(origin: .zero, size: project.composition.size)
                                         : boxes.values.reduce(first) { $0.union($1) }
        move(by: Alignment.align(boxes, edge, to: reference), name: edge.title)
    }

    /// Spaces three or more selected layers evenly, keeping the outer two.
    func distribute(_ axis: Snapping.Axis) {
        move(by: Alignment.distribute(arrangeableBoxes(), along: axis),
             name: axis == .x ? "Distribute Horizontally" : "Distribute Vertically")
    }

    private func arrangeableBoxes() -> [UUID: Box] {
        let scene = self.scene
        var boxes: [UUID: Box] = [:]
        for layer in arrangeable { boxes[layer.id] = scene.bounds(of: layer.id) }
        return boxes
    }

    /// Moves layers by composition-space amounts, as one undo step.
    private func move(by moves: [UUID: Vec2], name: String) {
        let scene = self.scene
        let moved = arrangeable.compactMap { layer -> Layer? in
            guard let d = moves[layer.id], abs(d.x) > 1e-9 || abs(d.y) > 1e-9 else { return nil }
            return layer.translated(by: parentDelta(d, for: layer.id, in: scene))
        }
        guard !moved.isEmpty else { return }
        perform(.batch([layerUpdate(moved)], name: name))
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

    static let pasteboardType = NSPasteboard.PasteboardType("com.nidhin.twine.layers")

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
            || board.string(forType: .string).map(FigmaImport.isPayload) == true
    }

    /// Pastes in place, in front of everything at the top level. Every pasted
    /// layer is a new layer with new ids, however many times it is pasted.
    func paste() {
        // A copy from the Twine plugin in Figma.
        if let text = NSPasteboard.general.string(forType: .string), FigmaImport.isPayload(text) { return pasteFromFigma(text) }
        // Copying clears the pasteboard, so it holds layers or actions, never both.
        if NSPasteboard.general.data(forType: Self.actionPasteboardType) != nil { return pasteActions() }
        guard let data = NSPasteboard.general.data(forType: Self.pasteboardType),
              let clipboard = try? JSONDecoder().decode(LayerClipboard.self, from: data) else { return }
        var map: [UUID: UUID] = [:]
        let copies = clipboard.layers.map { $0.duplicated(recordingIDs: &map) }.map { $0.remappingMasks(map) }
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
