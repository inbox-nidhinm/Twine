import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// The left panel: the project's name in the strip beside the traffic lights,
/// then the layer tree. The tree is for groupings and stacking order; the
/// timeline, a separate surface, is for actions.
struct LayersPanel: View {
    let document: ProjectDocument
    let store: ProjectStore
    @Bindable var editor: EditorModel
    let controller: EditorController

    @State private var renamingFile = false
    @State private var fileDraft = ""
    /// A new name shown at once while the file is moved to it, which takes a
    /// moment; the panel went back to the old name until it was done.
    @State private var pendingName: String?
    @State private var nameHover = false
    @FocusState private var fileFocused: Bool

    /// The groups and frames that are open, kept by the editor so they
    /// outlast the panel being hidden.
    private var expanded: Set<UUID> {
        get { editor.expandedLayers }
        nonmutating set { editor.expandedLayers = newValue }
    }
    /// Where a shift-click extends a run from.
    @State private var lastClicked: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            SectionHeader(title: "Layers")
                .overlay(alignment: .trailing) { soloSwitch }
            ScrollViewReader { list in
                ScrollView {
                    // Worked out once, not by every row scanning every layer.
                    let masks = controller.project.maskIDs
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { row in
                            LayerRow(row: row, editor: editor, controller: controller, isMask: masks.contains(row.id),
                                     isExpanded: expanded.contains(row.id),
                                     toggleExpanded: { toggle(row.id) },
                                     click: { click(row.id, NSEvent.modifierFlags) })
                                .id(row.id)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, Theme.panelPad)
                }
                .frame(maxHeight: .infinity)
                // A layer picked on the canvas, or one about to be renamed,
                // is brought into view: a turn on, once its group has opened.
                .onChange(of: editor.selection) { _, _ in reveal(in: list) }
                .onChange(of: editor.renaming) { _, id in if id != nil { reveal(in: list) } }
            }
        }
        .overlay(alignment: .topTrailing) {
            IconButton(icon: .home, help: "Home (⇧⌘H)") {
                HomeWindowController.shared.showWindow(nil)
            }
            .padding(.trailing, Theme.buttonInset)
            .padding(.top, Theme.panelPad - 6)
        }
        // Selecting something inside a folded group opens the group, so the
        // selection is never hidden in the list.
        .onChange(of: editor.selection) { _, selection in
            for id in selection { expanded.formUnion(store.project.ancestors(of: id)) }
        }
    }

    /// Scrolls just far enough to show the first selected row (or the one
    /// being renamed), if it is out of sight.
    private func reveal(in list: ScrollViewProxy) {
        DispatchQueue.main.async {
            let wanted = editor.renaming ?? rows.first { editor.selection.contains($0.id) }?.id
            if let wanted { list.scrollTo(wanted) }
        }
    }

    /// Shown while any layer is soloed, lit, and switches them all off: a
    /// solo left on inside a folded group hid everything else on the canvas
    /// with nothing to say why, and is kept with the file.
    @ViewBuilder private var soloSwitch: some View {
        let soloed = soloedLayers
        if !soloed.isEmpty {
            Button { controller.perform(.setSoloed(soloed, false)) } label: {
                IconView(.solo, size: 15)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: Theme.rowIconButton, height: Theme.listRow)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Only soloed layers are showing. Click to show them all")
            .padding(.trailing, Theme.buttonInset)
        }
    }

    private var soloedLayers: Set<UUID> {
        var ids: Set<UUID> = []
        store.project.forEachLayer { if $0.isSoloed { ids.insert($0.id) } }
        return ids
    }

    // MARK: Rows

    /// The tree flattened in the order the panel shows it: front at the top.
    private var rows: [LayerRowItem] {
        var out: [LayerRowItem] = []
        func walk(_ layers: [Layer], depth: Int, inTemplate: Bool = false) {
            for layer in layers.reversed() {
                out.append(LayerRowItem(layer: layer, depth: depth, isSlot: inTemplate))
                if layer.isGroup, expanded.contains(layer.id) { walk(layer.children, depth: depth + 1, inTemplate: layer.isTemplate) }
            }
        }
        walk(store.project.layers, depth: 0)
        return out
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    /// Click selects; Command adds or removes one; Shift selects the run from
    /// the last one clicked.
    private func click(_ id: UUID, _ modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.shift), let from = lastClicked, let a = rows.firstIndex(where: { $0.id == from }),
           let b = rows.firstIndex(where: { $0.id == id }) {
            // Through the controller, which lets go of the actions of
            // layers that leave the selection.
            controller.select(rows[min(a, b)...max(a, b)].map(\.id))
        } else if modifiers.contains(.command) {
            controller.select([id], extending: true)
            lastClicked = id
        } else {
            controller.select([id])
            lastClicked = id
        }
        // Delete, Duplicate and Copy are for layers after a click here, as
        // after one on the canvas, not for the actions last clicked.
        editor.focus = .canvas
    }

    // MARK: The file

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if renamingFile {
                TextField("", text: $fileDraft)
                    .textFieldStyle(.plain)
                    .font(ThemeFont.title)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($fileFocused)
                    .onAppear { DispatchQueue.main.async { fileFocused = true } }
                    .onSubmit(commitFileName)
                    .onExitCommand { renamingFile = false }
                    .onChange(of: fileFocused) { _, now in if !now, renamingFile { commitFileName() } }
            } else {
                Text(pendingName ?? document.name)
                    .font(ThemeFont.title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                        .fill(nameHover ? Theme.rowHover : .clear))
                    .padding(.horizontal, -4)
                    .contentShape(Rectangle())
                    .onHover { nameHover = $0 }
                    .help("Rename")
                    .highPriorityGesture(TapGesture().onEnded {
                        fileDraft = document.name
                        renamingFile = true
                    })
            }
            Text(summary)
                .font(ThemeFont.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.panelPad)
        .padding(.top, 44)
        .padding(.bottom, Theme.panelPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var summary: String {
        let c = store.project.composition
        return "\(c.width) × \(c.height) · \(c.frameRate.label) fps · \(TimeFormat.seconds(c.duration))"
    }

    private func commitFileName() {
        renamingFile = false
        let wanted = fileDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !wanted.isEmpty, wanted != document.name, !wanted.contains("/") { pendingName = wanted }
        document.rename(to: fileDraft) { _ in pendingName = nil }
        UnitField.leaveField()
    }
}

struct LayerRowItem: Identifiable {
    let layer: Layer
    let depth: Int
    /// One of a template's slots.
    var isSlot = false
    var id: UUID { layer.id }
}

/// One layer in the list: its kind, its name, and the switches that act on
/// it. The switches show under the pointer, or while they are on, so a list
/// of ordinary layers stays quiet.
private struct LayerRow: View {
    let row: LayerRowItem
    let editor: EditorModel
    let controller: EditorController
    /// Used as another layer's mask.
    let isMask: Bool
    let isExpanded: Bool
    let toggleExpanded: () -> Void
    let click: () -> Void

    @State private var hovering = false
    @State private var draft = ""
    /// Where a drag over this row would land, while one is.
    @State private var dropEdge: DropEdge?
    @FocusState private var nameFocused: Bool

    private var layer: Layer { row.layer }
    private var selected: Bool { editor.selection.contains(layer.id) }
    /// Hovered here or on the canvas: either way the row shows its hover
    /// state, switches and all.
    private var lit: Bool { hovering || editor.hoveredLayer == layer.id }


    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(row.depth) * 12, height: 1)
            if layer.isGroup {
                Button(action: toggleExpanded) {
                    IconView(.chevronRight, size: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: Theme.disclosure, height: Theme.listRow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: Theme.disclosure, height: Theme.hairline)
            }
            // An empty slot reads as a picture still to come.
            IconView(isMask ? .mask : row.isSlot && layer.slotMedia == nil ? .image : layer.icon, size: 15)
                .opacity(row.isSlot && layer.slotMedia == nil ? 0.45 : 1)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                .help(isMask ? "A mask: the layers in front of it in its group show only where it draws" : "")
            name
            Spacer(minLength: 0)
            if layer.isSoloed || lit {
                toggle(.solo, on: layer.isSoloed, help: layer.isSoloed ? "Unsolo" : "Solo: show only this") {
                    controller.perform(.setSoloed(switched, !layer.isSoloed))
                }
            }
            if layer.isLocked || lit {
                toggle(layer.isLocked ? .lock : .unlock, on: layer.isLocked, help: layer.isLocked ? "Unlock" : "Lock") {
                    controller.perform(.setLocked(switched, !layer.isLocked))
                }
            }
            if !layer.isVisible || lit {
                toggle(layer.isVisible ? .eye : .eyeSlash, on: !layer.isVisible, help: layer.isVisible ? "Hide" : "Show") {
                    controller.perform(.setVisible(switched, !layer.isVisible))
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(height: Theme.listRow)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
            .fill(selected ? Theme.rowSelected : lit ? Theme.rowHover : .clear))
        // Where a dragged layer will land: a line along the top for in
        // front of this row, along the bottom for behind it, and the row
        // outlined for inside a group. One outline for all three left the
        // result to be guessed.
        .overlay(alignment: dropEdge == .below ? .bottom : .top) {
            switch dropEdge {
            case .into: RoundedRectangle(cornerRadius: Theme.radiusRow).strokeBorder(Theme.accent, lineWidth: 1.5)
            case .above, .below: Capsule().fill(Theme.accent).frame(height: 2)
            case nil: EmptyView()
            }
        }
        .opacity(layer.isVisible ? 1 : 0.5)
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            // Shared with the canvas, which outlines the layer. Leaving only
            // clears it if nothing else has taken it since.
            if inside { editor.hoveredLayer = layer.id } else if editor.hoveredLayer == layer.id { editor.hoveredLayer = nil }
        }
        // A double-click renames, as in Figma. Read from the click itself
        // rather than a second tap gesture, which would hold every single
        // click back until it knew no second one was coming.
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 { editor.renaming = layer.id } else { click() }
        }
        .rightClickMenu(menu)
        .draggable(dragged.map(\.uuidString).joined(separator: ",")) {
            Text(dragged.count > 1 ? "\(dragged.count) layers" : layer.name)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: Theme.control)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        }
        .onDrop(of: [.utf8PlainText], delegate: RowDrop(edge: { edge(at: $0) }, shown: $dropEdge) { ids, edge in
            _ = drop(ids, edge: edge)
        })
    }

    /// What a drag of this row carries: every selected layer when the row
    /// is one of them, otherwise the row's own.
    private var dragged: [UUID] {
        selected && editor.selection.count > 1 ? controller.selectedLayers.map(\.id) : [layer.id]
    }

    @ViewBuilder private var name: some View {
        if editor.renaming == layer.id {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .focused($nameFocused)
                .onAppear {
                    draft = layer.name
                    DispatchQueue.main.async { nameFocused = true }
                }
                .onSubmit(commit)
                .onExitCommand { editor.renaming = nil }
                .onChange(of: nameFocused) { _, now in if !now, editor.renaming == layer.id { commit() } }
        } else {
            Text(layer.name)
                .font(ThemeFont.label)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private func commit() {
        editor.renaming = nil
        if draft != layer.name { controller.perform(.renameLayer(layer.id, draft)) }
        // The field goes, so the keyboard goes back to the canvas: left
        // nowhere, Space and the tool keys did nothing until a click.
        UnitField.leaveField()
    }

    /// The layers a switch on this row changes: every selected layer when
    /// the row is one of them, as the timeline's eye and the layer menu do.
    private var switched: Set<UUID> { controller.switched(by: layer) }

    private func toggle(_ icon: Icon, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: 15)
                .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: Theme.rowIconButton, height: Theme.listRow)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func edge(at location: CGPoint) -> DropEdge {
        let h = Theme.listRow
        if layer.isGroup, location.y > h / 3, location.y < h * 2 / 3 { return .into }
        return location.y < h / 2 ? .above : .below
    }

    /// Above a row is in front of it, below is behind it, and the middle of a
    /// group is inside it, in front of what it holds.
    private func drop(_ ids: [UUID], edge: DropEdge) -> Bool {
        let project = controller.project
        let moving = ids.filter { $0 != layer.id }
        guard !moving.isEmpty else { return false }
        // Moved so they stay where they are on the canvas, whatever group or
        // frame they leave or join.
        if edge == .into {
            return controller.perform(Arrangement.move(moving, to: layer.id, index: nil, in: project))
        }
        guard let location = project.location(of: layer.id) else { return false }
        let siblings = (location.parentID.flatMap { project.layer(withID: $0)?.children } ?? project.layers)
            .filter { !moving.contains($0.id) }
        guard let at = siblings.firstIndex(where: { $0.id == layer.id }) else { return false }
        return controller.perform(Arrangement.move(moving, to: location.parentID, index: edge == .above ? at + 1 : at, in: project))
    }

    private func menu() -> [MenuEntry] {
        if !selected { controller.select([layer.id]) }
        editor.focus = .canvas
        return controller.layerMenu(for: layer)
    }
}

extension EditorController {
    /// What a right-click on a layer offers, in the layers panel and on the
    /// canvas alike. The layer is selected first.
    func layerMenu(for layer: Layer) -> [MenuEntry] {
        var entries: [MenuEntry] = [
            // The name is edited in its row, so the panel is shown first.
            .item("Rename") {
                self.editor.showLayers = true
                self.editor.renaming = layer.id
            },
            .item("Duplicate") { self.duplicateSelectedLayers() },
            .separator,
            .item("Cut") { self.copySelectedLayers(); self.deleteSelectedLayers() },
            .item("Copy") { self.copySelectedLayers() },
            .item("Paste", disabled: !canPaste) { self.paste() },
            .separator,
            .item("Bring to Front") { self.restack(.front) },
            .item("Send to Back") { self.restack(.back) },
            .separator,
            .item("Group Selection") { self.groupSelection() },
            .item("Frame Selection") { self.frameSelection() },
        ]
        if layer.isGroup { entries.append(.item("Ungroup") { self.ungroupSelection() }) }
        entries.append(layer.isMask ? .item("Remove Mask") { self.removeMask(layer.id) }
                                    : .item("Use as Mask") { self.useSelectionAsMask() })
        // Style is the design's, so it is copied and pasted in Design.
        if editor.mode == .design, LayerStyle.takes(layer) {
            entries += [.separator, .item("Copy Style") { self.copyStyle(of: layer) }]
            if canPasteStyle { entries.append(.item("Paste Style") { self.pasteStyle() }) }
        }
        // Copied actions go onto this layer, or every selected one it is among.
        if editor.mode == .animate, canPasteActions {
            let onto = editor.selection.contains(layer.id) ? selectedLayers : [layer]
            entries += [.separator, .item(copiedActionCount == 1 ? "Paste Action" : "Paste Actions") { self.pasteActions(onto: onto) }]
        }
        // Every selected layer when this is one of them, as Delete,
        // Duplicate and Group in this menu already take the selection.
        let ids = switched(by: layer)
        entries += [
            .separator,
            .item(layer.isSoloed ? "Unsolo" : "Solo") { self.perform(.setSoloed(ids, !layer.isSoloed)) },
            .item(layer.isLocked ? "Unlock" : "Lock") { self.perform(.setLocked(ids, !layer.isLocked)) },
            .item(layer.isVisible ? "Hide" : "Show") { self.perform(.setVisible(ids, !layer.isVisible)) },
            .separator,
            .item("Delete") { self.deleteSelectedLayers() },
        ]
        return entries
    }

    /// The layers a switch or menu item on `layer` changes: the whole
    /// selection when `layer` is in it, otherwise the layer alone.
    func switched(by layer: Layer) -> Set<UUID> {
        editor.selection.contains(layer.id) ? editor.selection : [layer.id]
    }
}

extension Layer {
    var icon: Icon {
        switch content {
        case .shape(let shape) where shape.pictureIndex != nil && shape.geometry.isRectangle:
            // A picture is a rectangle filled with it, but reads as a
            // picture. Any other shape with one is still that shape.
            return .image
        case .shape(let shape):
            switch shape.geometry {
            case .rectangle: return .rectangle
            case .ellipse: return .ellipse
            case .line: return .line
            case .polygon: return .polygon
            case .star: return .star
            case .path: return .pen
            }
        case .text: return .text
        case .video: return .video
        case .audio: return .audio
        // A template is a frame, but reads as its own kind.
        case .group(let g): return g.template != nil ? .templateLayer : g.frame == nil ? .group : .frame
        }
    }
}

enum TimeFormat {
    /// `5s`, `2.5s`, `1:05.25`.
    static func seconds(_ t: Double) -> String {
        let minutes = Int(t / 60)
        let rest = t - Double(minutes * 60)
        var s = String(format: "%.2f", rest)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if minutes == 0 { return s + "s" }
        return "\(minutes):" + (rest < 10 ? "0" : "") + s
    }

    /// `0:02.50`, the playhead readout.
    static func clock(_ t: Double) -> String {
        let minutes = Int(t / 60)
        let rest = t - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, rest)
    }
}

/// Where a layer dropped on a row lands: in front of it, inside it (a
/// group), or behind it.
private enum DropEdge: Sendable { case above, into, below }

/// A drag of layers over a row: says where it would land as the pointer
/// moves (a plain drop destination only says that it is over the row), and
/// hands over the layers when it is let go.
private struct RowDrop: DropDelegate {
    let edge: (CGPoint) -> DropEdge
    @Binding var shown: DropEdge?
    let perform: @MainActor @Sendable ([UUID], DropEdge) -> Void

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.utf8PlainText]) }
    func dropEntered(info: DropInfo) { shown = edge(info.location) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let now = edge(info.location)
        if shown != now { shown = now }
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { shown = nil }

    func performDrop(info: DropInfo) -> Bool {
        let at = edge(info.location)
        shown = nil
        guard let provider = info.itemProviders(for: [.utf8PlainText]).first else { return false }
        let perform = perform
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            let ids = ((text as? String) ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) }
            Task { @MainActor in perform(ids, at) }
        }
        return true
    }
}
