import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's inspector. It never shows design properties: with actions
/// selected it shows their fields; with only layers selected it offers the
/// actions they can take and the presets, added at the playhead; an
/// action's header offers the same, to add another without leaving it.
/// With nothing selected it is empty.
struct AnimationInspector: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    /// The preset picker stands in for the tiles until a preset is picked,
    /// it is closed, or the selection changes.
    @State private var pickingPreset = false

    var body: some View {
        let layers = controller.selectedLayers
        let actions = controller.selectedActions
        Group {
            // The picker stands in for whatever shows, an action's fields
            // included, so a preset can be added from anywhere.
            if pickingPreset && !layers.isEmpty {
                PresetPicker(presets: controller.availablePresets,
                             pick: { preset in
                                 pickingPreset = false
                                 controller.addPreset(preset)
                             },
                             close: { pickingPreset = false })
            } else if !actions.isEmpty {
                ActionInspector(controller: controller, actions: actions,
                                newActions: actionEntries(controller.availableActions),
                                pickPreset: { pickingPreset = true })
                    .id(actions.map(\.id))
            } else if !layers.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HeaderRow(title: "Actions") {}
                    ActionTiles(newActions: actionEntries(controller.availableActions),
                                hasPresets: !controller.availablePresets.isEmpty) { pickingPreset = true }
                        .padding(.horizontal, Theme.panelPad)
                }
                .padding(.bottom, Theme.panelPad)
            }
        }
        .onChange(of: layers.map(\.id)) { pickingPreset = false }
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
}

