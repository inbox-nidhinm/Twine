import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's inspector. It never shows design properties: with layers
/// selected it offers the actions they can take, added at the playhead.
/// With nothing selected it is empty.
struct AnimationInspector: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    var body: some View {
        let layers = controller.selectedLayers
        if !layers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HeaderRow(title: "Actions") {}
                AddActionButton(kinds: controller.availableActions) { controller.addAction($0) }
                    .padding(.horizontal, Theme.panelPad)
            }
            .padding(.bottom, Theme.panelPad)
        }
    }
}

/// A full-width button, shaped like the panel's menus, that opens the list
/// of actions to add.
private struct AddActionButton: View {
    let kinds: [ActionKind]
    let add: (ActionKind) -> Void

    @Environment(MenuHost.self) private var menus
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var body: some View {
        Button {
            menus.show(kinds.map { kind in .item(kind.defaultName) { add(kind) } },
                       at: CGPoint(x: frame.minX, y: frame.maxY + 4))
        } label: {
            HStack(spacing: 6) {
                IconView(.plus, size: 13)
                Text("Add Action")
                    .font(ThemeFont.label)
                Spacer(minLength: 0)
                IconView(.chevronDown, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(kinds.isEmpty ? Theme.textTertiary : Theme.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: Theme.panelRow + 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering && !kinds.isEmpty ? Theme.panelHover : Theme.panelRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(kinds.isEmpty)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .help("Adds an action at the playhead, half a second long.")
    }
}

