import SwiftUI
import MotionModel
import MotionEvaluation
import MotionEditing
import Theme

/// A template frame's own section, in Design: its pictures, the cards'
/// shape, where it rests, its recipe's settings, and Split into Layers.
struct TemplateSection: View {
    let layer: Layer
    let setup: TemplateSetup
    let controller: EditorController

    private let wells = [GridItem(.adaptive(minimum: Theme.pictureWell), spacing: 6)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: Templates.name(of: setup.kind)) {
                IconButton(icon: .plus, help: "Add a picture slot") {
                    controller.editTemplate(layer.id) { $0.slots.append(nil) }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                slots
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
    }

    // MARK: Pictures

    /// A well for each slot: a click chooses its picture, and a filled one
    /// can be emptied; an empty slot shows a plain card.
    private var slots: some View {
        LazyVGrid(columns: wells, alignment: .leading, spacing: 6) {
            ForEach(Array(setup.slots.enumerated()), id: \.offset) { index, media in
                SlotWell(image: media.flatMap(controller.preview(of:)), number: index + 1,
                         choose: { controller.chooseTemplatePicture(layer.id, slot: index) },
                         remove: {
                             controller.editTemplate(layer.id) { setup in
                                 if setup.slots[index] != nil { setup.slots[index] = nil } else if setup.slots.count > 1 { setup.slots.remove(at: index) }
                             }
                         },
                         filled: media != nil)
            }
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

/// One slot's picture, or its number on a plain well while empty. A click
/// chooses a picture; the corner button empties a filled slot, or takes an
/// empty one away.
private struct SlotWell: View {
    let image: CGImage?
    let number: Int
    let choose: () -> Void
    let remove: () -> Void
    let filled: Bool

    @State private var hovering = false

    var body: some View {
        Button(action: choose) {
            ZStack {
                if filled {
                    PictureWell(image: image)
                } else {
                    RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .fill(hovering ? Theme.panelHover : Theme.panelRaised)
                        .frame(width: Theme.pictureWell, height: Theme.pictureWell)
                        .overlay(Text("\(number)").font(ThemeFont.label).foregroundStyle(Theme.textTertiary))
                }
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                IconButton(icon: .close, help: filled ? "Empty this slot" : "Remove this slot", action: remove)
                    .scaleEffect(0.7)
                    .offset(x: 6, y: -6)
            }
        }
        .onHover { hovering = $0 }
        .help(filled ? "Choose another picture" : "Choose a picture")
    }
}
