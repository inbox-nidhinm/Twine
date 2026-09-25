import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's inspector. It never shows design properties: with layers
/// selected it offers the actions they can take, added at the playhead, and
/// lists the actions already on them. With nothing selected it is empty.
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
                ActionList(actions: actions(on: layers), layers: layers, frames: editor.showsFrames,
                           rate: controller.frameRate)
            }
            .padding(.bottom, Theme.panelPad)
        }
    }

    /// The selected layers' actions in the order they happen.
    private func actions(on layers: [Layer]) -> [Action] {
        let ids = Set(layers.map(\.id))
        return controller.project.actions.filter { ids.contains($0.targetLayerID) }.sorted {
            ($0.start, $0.rowOrder) < ($1.start, $1.rowOrder)
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

/// The actions on the selection, one line each: name and when it runs.
/// The timeline takes this over once it has action rows.
private struct ActionList: View {
    let actions: [Action]
    let layers: [Layer]
    let frames: Bool
    let rate: FrameRate

    var body: some View {
        VStack(spacing: 0) {
            ForEach(actions) { action in
                HStack(spacing: 6) {
                    Text(action.name)
                        .foregroundStyle(Theme.textPrimary)
                    if layers.count > 1, let layer = layers.first(where: { $0.id == action.targetLayerID }) {
                        Text(layer.name)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Text(timing(action))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                .font(ThemeFont.label)
                .lineLimit(1)
                .frame(height: Theme.panelRow)
                .opacity(action.isEnabled ? 1 : 0.5)
            }
        }
        .padding(.horizontal, Theme.panelPad)
    }

    private func timing(_ action: Action) -> String {
        func t(_ s: Double) -> String { frames ? "\(rate.frame(at: s))f" : String(format: "%.2fs", s) }
        return action.isInstant ? t(action.start) : "\(t(action.start)) to \(t(action.end))"
    }
}
