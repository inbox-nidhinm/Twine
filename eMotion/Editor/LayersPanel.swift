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
    @State private var nameHover = false
    @FocusState private var fileFocused: Bool

    @State private var expanded: Set<UUID> = []
    /// Where a shift-click extends a run from.
    @State private var lastClicked: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            SectionHeader(title: "Layers")
            ScrollView {
                // Worked out once, not by every row scanning every layer.
                let masks = controller.project.maskSourceIDs
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        LayerRow(row: row, editor: editor, controller: controller, isMask: masks.contains(row.id),
                                 isExpanded: expanded.contains(row.id),
                                 toggleExpanded: { toggle(row.id) },
                                 click: { click(row.id, NSEvent.modifierFlags) })
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, Theme.panelPad)
            }
            .frame(maxHeight: .infinity)
        }
        .overlay(alignment: .topTrailing) {
            IconButton(icon: .home, help: "Home (⇧⌘H)") {
                HomeWindowController.shared.showWindow(nil)
            }
            .padding(.trailing, Theme.panelPad - 4)
            .padding(.top, Theme.panelPad - 6)
        }
        // Selecting something inside a folded group opens the group, so the
        // selection is never hidden in the list.
        .onChange(of: editor.selection) { _, selection in
            for id in selection { expanded.formUnion(store.project.ancestors(of: id)) }
        }
    }

    // MARK: Rows

    /// The tree flattened in the order the panel shows it: front at the top.
    private var rows: [LayerRowItem] {
        var out: [LayerRowItem] = []
        func walk(_ layers: [Layer], depth: Int) {
            for layer in layers.reversed() {
                out.append(LayerRowItem(layer: layer, depth: depth))
                if layer.isGroup, expanded.contains(layer.id) { walk(layer.children, depth: depth + 1) }
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
            editor.selection = Set(rows[min(a, b)...max(a, b)].map(\.id))
        } else if modifiers.contains(.command) {
            controller.select([id], extending: true)
            lastClicked = id
        } else {
            controller.select([id])
            lastClicked = id
        }
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
                Text(document.name)
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
        document.rename(to: fileDraft)
    }
}

struct LayerRowItem: Identifiable {
    let layer: Layer
    let depth: Int
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
    @State private var dropTargeted = false
    @FocusState private var nameFocused: Bool

    private var layer: Layer { row.layer }
    private var selected: Bool { editor.selection.contains(layer.id) }
    /// Hovered here or on the canvas: either way the row shows its hover
    /// state, switches and all.
    private var lit: Bool { hovering || editor.hoveredLayer == layer.id }

    enum DropEdge { case above, into, below }

    var body: some View {
        HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(row.depth) * 12, height: 1)
            if layer.isGroup {
                Button(action: toggleExpanded) {
                    IconView(.chevronRight, size: 12)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 14, height: Theme.listRow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            IconView(isMask ? .mask : layer.icon, size: 15)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
                .help(isMask ? "Masking another layer: it shows only through that layer" : "")
            name
            Spacer(minLength: 0)
            if layer.isSoloed || lit {
                toggle(.solo, on: layer.isSoloed, help: layer.isSoloed ? "Unsolo" : "Solo: show only this") {
                    controller.perform(.setSoloed([layer.id], !layer.isSoloed))
                }
            }
            if layer.isLocked || lit {
                toggle(layer.isLocked ? .lock : .unlock, on: layer.isLocked, help: layer.isLocked ? "Unlock" : "Lock") {
                    controller.perform(.setLocked([layer.id], !layer.isLocked))
                }
            }
            if !layer.isVisible || lit {
                toggle(layer.isVisible ? .eye : .eyeSlash, on: !layer.isVisible, help: layer.isVisible ? "Hide" : "Show") {
                    controller.perform(.setVisible([layer.id], !layer.isVisible))
                }
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .frame(height: Theme.listRow)
        .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
            .fill(selected ? Theme.rowSelected : lit ? Theme.rowHover : .clear))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: Theme.radiusRow).strokeBorder(Theme.accent, lineWidth: 1.5)
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
        .onTapGesture(perform: click)
        .rightClickMenu(menu)
        .draggable(layer.id.uuidString) {
            Text(layer.name)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: Theme.control)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        }
        .dropDestination(for: String.self) { items, location in
            dropTargeted = false
            return drop(items.compactMap(UUID.init(uuidString:)), edge: edge(at: location))
        } isTargeted: { dropTargeted = $0 }
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
    }

    private func toggle(_ icon: Icon, on: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: 15)
                .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: 22, height: Theme.listRow)
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
        var entries: [MenuEntry] = [
            .item("Rename") { editor.renaming = layer.id },
            .item("Duplicate") { controller.duplicateSelection() },
            .item("Group Selection") { controller.groupSelection() },
            .item("Frame Selection") { controller.frameSelection() },
        ]
        if layer.isGroup { entries.append(.item("Ungroup") { controller.ungroupSelection() }) }
        entries += [
            .separator,
            .item(layer.isSoloed ? "Unsolo" : "Solo") { controller.perform(.setSoloed([layer.id], !layer.isSoloed)) },
            .item(layer.isLocked ? "Unlock" : "Lock") { controller.perform(.setLocked([layer.id], !layer.isLocked)) },
            .item(layer.isVisible ? "Hide" : "Show") { controller.perform(.setVisible([layer.id], !layer.isVisible)) },
            .separator,
            .item("Delete") { controller.deleteSelection() },
        ]
        return entries
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
        case .group(let g): return g.frame == nil ? .group : .frame
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
