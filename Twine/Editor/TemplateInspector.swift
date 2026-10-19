import SwiftUI
import MotionModel
import MotionEvaluation
import MotionEditing
import Theme

/// A template frame's own section, in Design: the cards' shape, where it
/// rests, its recipe's settings, and Split into Layers. Its pictures are its
/// slots, listed under it in the layers panel; files dropped here are added
/// as slots after the last.
struct TemplateSection: View {
    let layer: Layer
    let setup: TemplateSetup
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: Templates.name(of: setup.kind)) {
                IconButton(icon: .plus, help: "Add a slot") { controller.addTemplateSlot(layer.id) }
            }
            VStack(alignment: .leading, spacing: 10) {
                cardRows
                LabeledRow(label: "Rests at") {
                    UnitField(value: setup.pose * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                        controller.editTemplate(layer.id) { $0.pose = min(max(v / 100, 0), 1) }
                    }
                }
                .help("Where in its loop it rests: what Design shows, and what shows before and after its bar.")
                ForEach(TemplateRecipes.controls(setup.kind)) { control in
                    row(control)
                }
                PanelButton(title: "Split into Layers", icon: .group) { controller.splitTemplate(layer.id) }
                    .help("Turns it into an ordinary frame in 3D of cards, with its motion as actions you can edit one by one.")
            }
            .gridBody()
        }
        .sectionPadding()
        .dropDestination(for: URL.self) { urls, _ in
            controller.setTemplateMedia(layer.id, from: layer.templateSlots.count, urls: urls)
            return true
        }
    }

    // MARK: Cards

    @ViewBuilder private var cardRows: some View {
        LabeledRow(label: "Shape") {
            MenuLabel(title: setup.ratio.title, entries: CardRatio.allCases.map { ratio in
                .item(ratio.title, checked: ratio == setup.ratio) { controller.editTemplate(layer.id) { $0.ratio = ratio } }
            })
        }
        .help("The cards' shape: Auto takes each picture's own.")
        HStack(spacing: 8) {
            UnitField(unit: "Radius", value: setup.cornerRadius * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 50 }) { v in
                controller.editTemplate(layer.id) { $0.cornerRadius = v / 100 }
            }
            .help("How round the cards' corners are, as a share of their shorter side.")
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
        }
        CheckRow(label: "Shadow", isOn: setup.shadow) { controller.editTemplate(layer.id) { $0.shadow.toggle() } }
            .help("A soft shadow under every card.")
    }

    // MARK: Settings

    @ViewBuilder private func row(_ control: TemplateControl) -> some View {
        switch control.kind {
        case .number(let lo, let hi, let standard, let unit):
            let value = setup.settings[control.key]?.number ?? standard
            LabeledRow(label: control.name) {
                UnitField(value: value, decimals: unit == .plain ? 2 : 0, suffix: Self.suffix(unit),
                          accepts: { $0 >= lo && $0 <= hi }) { v in
                    controller.editTemplate(layer.id) { $0.settings[control.key] = .number(v) }
                }
            }
            .help(control.help)
        case .choice(let options, let standard):
            let chosen = setup.settings[control.key]?.choice ?? standard
            if options.count <= 3 {
                VStack(alignment: .leading, spacing: 6) {
                    Text(control.name).font(ThemeFont.label).foregroundStyle(Theme.textSecondary)
                    SegmentRow(selection: chosen, options: options.map(\.key),
                               title: { key in options.first { $0.key == key }?.title ?? key }) { key in
                        controller.editTemplate(layer.id) { $0.settings[control.key] = .choice(key) }
                    }
                }
                .help(control.help)
            } else {
                LabeledRow(label: control.name) {
                    MenuLabel(title: options.first { $0.key == chosen }?.title ?? chosen, entries: options.map { option in
                        .item(option.title, checked: option.key == chosen) {
                            controller.editTemplate(layer.id) { $0.settings[control.key] = .choice(option.key) }
                        }
                    })
                }
                .help(control.help)
            }
        }
    }

    private static func suffix(_ unit: TemplateUnit) -> String {
        switch unit {
        case .percent: "%"
        case .degrees: "°"
        case .count, .plain: ""
        }
    }
}

/// A template's slot, selected in the layers panel: what it shows, a way
/// to choose another picture or video (or drop one here), and to empty it.
/// Shown in place of the layer's own sections, in both modes: a slot is
/// never drawn itself, so it has no place, size or look to set.
struct TemplateSlotSection: View {
    let slot: Layer
    let template: Layer
    let index: Int
    let controller: EditorController

    @State private var targeted = false

    private var media: UUID? { slot.slotMedia }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusWell)
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Slot \(index + 1)") {}
            VStack(alignment: .leading, spacing: 10) {
                Button { controller.chooseTemplatePicture(template.id, slot: index) } label: {
                    ZStack {
                        shape.fill(targeted ? Theme.panelHover : Theme.panelRaised)
                        if let media, let image = controller.preview(of: media) {
                            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                        } else {
                            Text(TemplateSlots.emptyName).font(ThemeFont.label).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4.0 / 3, contentMode: .fit)
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(targeted ? Theme.textSecondary : Theme.edge, lineWidth: 1))
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .help(media == nil ? "Choose a picture or video, or drop one here" : "Choose another picture or video, or drop one here")
                PanelButton(title: media == nil ? "Choose Picture or Video" : "Replace", icon: .image) {
                    controller.chooseTemplatePicture(template.id, slot: index)
                }
                if media != nil {
                    PanelButton(title: "Empty Slot", icon: .close) { controller.emptyTemplateSlot(template.id, slot: index) }
                        .help("Its cards show a sample picture again.")
                }
            }
            .gridBody()
        }
        .sectionPadding()
        .dropDestination(for: URL.self) { urls, _ in
            controller.setTemplateMedia(template.id, from: index, urls: urls)
            return true
        } isTargeted: { targeted = $0 }
    }
}
