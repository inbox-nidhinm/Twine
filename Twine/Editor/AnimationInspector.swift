import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's inspector. It never shows a layer's design properties:
/// with actions selected it shows their fields; with only layers selected
/// it lists the actions they have, each a click away, then New Action and
/// Select Preset, added at the playhead, under a sound's level when one
/// sound or video is selected; the foot of an action's fields offers the
/// same two buttons in the same place, and for a preset bar, Swap Preset.
/// With nothing selected it shows the composition, as Design does.
/// Templates is the last button in every state but an action's; with
/// layers selected, their pictures go into the one picked.
struct AnimationInspector: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    /// The preset picker stands in for the tiles until a preset is picked,
    /// it is closed, or the selection changes.
    @State private var pickingPreset = false
    /// The picker is up to swap the selected preset bars rather than add.
    @State private var swappingPreset = false
    /// The template picker stands in for the tiles until one is picked or
    /// it is closed.
    @State private var pickingTemplate = false

    var body: some View {
        let layers = controller.selectedLayers
        let actions = controller.selectedActions
        // One sound or video with sound shows its level, over its actions
        // or under its Play bar's fields.
        let sound = layers.count == 1 && controller.project.hasSound(layers[0]) ? layers[0] : nil
        Group {
            // The picker stands in for whatever shows, an action's fields
            // included, so a preset can be added from anywhere.
            if pickingTemplate {
                TemplatePicker(pick: { info in
                                   pickingTemplate = false
                                   controller.addTemplate(info.kind)
                               },
                               close: { pickingTemplate = false })
            } else if swappingPreset && !controller.selectedPresetBars.isEmpty {
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
            } else if layers.count == 1, let slot = controller.templateSlot(layers[0].id) {
                // A slot has nothing to animate; what it holds is set here too.
                TemplateSlotSection(slot: layers[0], template: slot.template, index: slot.index, controller: controller)
            } else if !layers.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    if let sound {
                        LayerSoundSection(layer: sound, controller: controller)
                        PanelDivider()
                    }
                    LayerActionsSection(layers: layers, controller: controller)
                    PanelDivider()
                    AddAnother(newActions: actionEntries(controller.availableActions),
                               hasPresets: !controller.availablePresets.isEmpty) { pickingPreset = true }
                        .gridBody()
                        .padding(.vertical, Theme.panelPad)
                    PanelDivider()
                    templates
                }
            } else {
                // Nothing selected: the composition, as in Design.
                VStack(alignment: .leading, spacing: 0) {
                    CompositionSection(store: controller.store)
                    PanelDivider()
                    templates
                }
            }
        }
        .onChange(of: layers.map(\.id)) { pickingPreset = false; swappingPreset = false }
        .onChange(of: actions.map(\.id)) { swappingPreset = false }
    }
}

extension AnimationInspector {
    /// Templates, the same small button wherever it shows.
    private var templates: some View {
        PanelButton(title: "Templates", icon: .template) { pickingTemplate = true }
            .help("Picks a whole scene of cards, a ring, a globe or a tunnel, to fill with your pictures; selected pictures and videos go into its slots.")
            .gridBody()
            .padding(.vertical, Theme.panelPad)
    }

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


/// The actions the selected layers have, in the order they start: each a
/// row with its icon, its name and when it runs, which selects it.
private struct LayerActionsSection: View {
    let layers: [Layer]
    let controller: EditorController

    var body: some View {
        let ids = Set(layers.map(\.id))
        let actions = controller.project.actions.filter { ids.contains($0.targetLayerID) }
            .sorted { ($0.start, $0.duration) < ($1.start, $1.duration) }
        VStack(alignment: .leading, spacing: Theme.space2) {
            HeaderRow(title: layers.count == 1 ? layers[0].name : "\(layers.count) layers") {}
            ForEach(actions) { action in
                ActionRow(action: action, timing: timing(action)) { controller.selectActions([action.id]) }
            }
        }
        .sectionPadding(empty: actions.isEmpty)
    }

    /// When it starts and ends, in frames or seconds as the timeline shows.
    private func timing(_ action: Action) -> String {
        let rate = controller.frameRate
        func shown(_ t: Double) -> String {
            controller.editor.showsFrames ? String(rate.frame(at: t)) : UnitField.trimmed(t, 2)
        }
        let unit = controller.editor.showsFrames ? "f" : "s"
        return action.isInstant ? "\(shown(action.start)) \(unit)"
                                : "\(shown(action.start)) → \(shown(action.start + action.duration)) \(unit)"
    }
}

private struct ActionRow: View {
    let action: Action
    let timing: String
    let select: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: select) {
            HStack(spacing: Theme.space6) {
                IconView(action.spec.kind.icon, size: Theme.iconRow)
                    .foregroundStyle(Theme.textTertiary)
                Text(action.name)
                    .font(ThemeFont.label)
                    .foregroundStyle(action.isEnabled ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: Theme.space4)
                Text(timing)
                    .font(ThemeFont.unit)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Theme.space8)
            .frame(height: Theme.button)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(hovering ? Theme.rowHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .padding(.horizontal, Theme.panelPad - Theme.space8)
        .help("Shows this action's settings")
    }
}
