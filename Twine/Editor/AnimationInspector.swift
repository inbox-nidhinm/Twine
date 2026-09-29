import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's inspector. It never shows design properties: with actions
/// selected it shows their fields; with only layers selected it offers the
/// actions they can take and the presets, added at the playhead, under a
/// sound's level when one sound or video is selected; the foot of an
/// action's fields offers the same, to add another without leaving it,
/// and for a preset bar, Swap Preset, to put another in its place.
/// With nothing selected it is empty.
struct AnimationInspector: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    /// The preset picker stands in for the tiles until a preset is picked,
    /// it is closed, or the selection changes.
    @State private var pickingPreset = false
    /// The picker is up to swap the selected preset bars rather than add.
    @State private var swappingPreset = false

    var body: some View {
        let layers = controller.selectedLayers
        let actions = controller.selectedActions
        // One sound or video with sound shows its level, over its actions
        // or under its Play bar's fields.
        let sound = layers.count == 1 && controller.project.hasSound(layers[0]) ? layers[0] : nil
        Group {
            // The picker stands in for whatever shows, an action's fields
            // included, so a preset can be added from anywhere.
            if swappingPreset && !controller.selectedPresetBars.isEmpty {
                PresetPicker(presets: controller.swappablePresets, swapping: true,
                             pick: { preset in
                                 swappingPreset = false
                                 controller.swapPresets(to: preset)
                             },
                             close: { swappingPreset = false })
            } else if pickingPreset && !layers.isEmpty {
                PresetPicker(presets: controller.availablePresets,
                             pick: { preset in
                                 pickingPreset = false
                                 controller.addPreset(preset)
                             },
                             close: { pickingPreset = false })
            } else if !actions.isEmpty {
                ActionInspector(controller: controller, actions: actions,
                                newActions: actionEntries(controller.availableActions),
                                pickPreset: { pickingPreset = true },
                                swapPreset: controller.selectedPresetBars.isEmpty ? nil : { swappingPreset = true },
                                sound: actions.allSatisfy { $0.spec.kind == .play } ? sound : nil)
                    .id(actions.map(\.id))
            } else if !layers.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if let sound {
                        LayerSoundSection(layer: sound, controller: controller)
                        PanelDivider()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HeaderRow(title: "Actions") {}
                        ActionTiles(newActions: actionEntries(controller.availableActions),
                                    hasPresets: !controller.availablePresets.isEmpty) { pickingPreset = true }
                            .padding(.horizontal, Theme.panelPad)
                    }
                    .padding(.bottom, Theme.panelPad)
                }
            }
        }
        .onChange(of: layers.map(\.id)) { pickingPreset = false; swappingPreset = false }
        .onChange(of: actions.map(\.id)) { swappingPreset = false }
    }
}

extension AnimationInspector {
    /// Grouped under Transform, Style and Blur, leaving out empty groups,
    /// each with its action's icon.
    private func actionEntries(_ kinds: [ActionKind]) -> [MenuEntry] {
        ActionCategory.allCases.flatMap { category -> [MenuEntry] in
            let items = kinds.filter { $0.category == category }
            guard !items.isEmpty else { return [] }
            return [.header(category.title)] + items.map { kind in .item(kind.defaultName, icon: kind.icon) { controller.addAction(kind) } }
        }
    }
}

