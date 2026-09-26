import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's inspector. It never shows design properties: with actions
/// selected it shows their fields; with only layers selected it offers the
/// actions they can take, added at the playhead. With nothing selected it
/// is empty.
struct AnimationInspector: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    var body: some View {
        let layers = controller.selectedLayers
        let actions = controller.selectedActions
        if !actions.isEmpty {
            ActionInspector(controller: controller, actions: actions)
                .id(actions.map(\.id))
        } else if !layers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HeaderRow(title: "Actions") {}
                Group {
                    AddMenuButton(title: "Add Action", icon: .plus, entries: actionEntries(controller.availableActions),
                                  help: "Adds an action at the playhead, half a second long.")
                    AddMenuButton(title: "Add Preset", icon: .preset, entries: presetEntries(controller.availablePresets),
                                  help: "Adds a ready-made animation at the playhead: ordinary actions you can edit afterwards.")
                }
                .padding(.horizontal, Theme.panelPad)
            }
            .padding(.bottom, Theme.panelPad)
        }
    }
}

extension AnimationInspector {
    /// Grouped under Transform, Style and Blur, leaving out empty groups.
    private func actionEntries(_ kinds: [ActionKind]) -> [MenuEntry] {
        ActionCategory.allCases.flatMap { category -> [MenuEntry] in
            let items = kinds.filter { $0.category == category }
            guard !items.isEmpty else { return [] }
            return [.header(category.title)] + items.map { kind in .item(kind.defaultName) { controller.addAction(kind) } }
        }
    }

    /// Grouped under Entrances, Exits and Emphasis.
    private func presetEntries(_ presets: [Preset]) -> [MenuEntry] {
        PresetCategory.allCases.flatMap { category -> [MenuEntry] in
            let items = presets.filter { $0.category == category }
            guard !items.isEmpty else { return [] }
            return [.header(category.title)] + items.map { preset in .item(preset.name) { controller.addPreset(preset) } }
        }
    }
}

/// A full-width button, shaped like the panel's menus, that opens a list of
/// things to add.
private struct AddMenuButton: View {
    let title: String
    let icon: Icon
    let entries: [MenuEntry]
    let help: String

    @Environment(MenuHost.self) private var menus
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var body: some View {
        Button {
            menus.show(entries, at: CGPoint(x: frame.minX, y: frame.maxY + 4))
        } label: {
            HStack(spacing: 6) {
                IconView(icon, size: 13)
                Text(title)
                    .font(ThemeFont.label)
                Spacer(minLength: 0)
                IconView(.chevronDown, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(entries.isEmpty ? Theme.textTertiary : Theme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: Theme.panelRow + 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering && !entries.isEmpty ? Theme.panelHover : Theme.panelRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(entries.isEmpty)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .help(help)
    }
}

