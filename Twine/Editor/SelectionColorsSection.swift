import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Figma's Selection colours: every colour and gradient used inside a group,
/// a frame or several layers, each once, changed everywhere it is used from
/// here (`SelectionColors`). Closed, as it starts for each selection, its
/// header shows the first few as small swatches and how many more there
/// are; a click opens the full list (27 November 2026, as in Figma). A
/// colour is a row as a fill's is; a gradient is a row that opens its stops
/// under it. Shows nothing when there is no colour inside, divider included.
struct SelectionColorsSection: View {
    let ids: [UUID]
    let controller: EditorController

    /// How many swatches the closed header shows before its count.
    private static let peeked = 3

    @State private var isOpen = false
    /// The gradient whose stops are open, by its first place.
    @State private var open: SelectionColors.Place?
    @State private var pickedStop: Int?

    var body: some View {
        let entries = SelectionColors.entries(in: controller.project, under: ids)
        if !entries.isEmpty {
            PanelDivider()
            VStack(alignment: .leading, spacing: Theme.space8) {
                if isOpen {
                    HeaderRow(title: "Selection colours") {
                        IconButton(icon: .chevronUp, help: "Hide the colours") { isOpen = false }
                    }
                    VStack(alignment: .leading, spacing: Theme.space8) {
                        ForEach(entries) { entry in
                            switch entry.look {
                            case .color(let color): colorRow(color, places: entry.places)
                            case .gradient(let g, let kind): gradientRows(g, kind: kind, entry: entry)
                            }
                        }
                    }
                    .gridBody()
                } else {
                    Button { isOpen = true } label: {
                        HeaderRow(title: "Selection colours") { peek(entries) }
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show every colour inside, to change it wherever it is used")
                }
            }
            .sectionPadding(empty: !isOpen)
            .onChange(of: ids) { _, _ in
                isOpen = false
                open = nil
                pickedStop = nil
            }
        }
    }

    /// The first few colours as small swatches, then how many more.
    private func peek(_ entries: [SelectionColors.Entry]) -> some View {
        HStack(spacing: Theme.space4) {
            ForEach(entries.prefix(Self.peeked)) { entry in
                switch entry.look {
                case .color(let color): PaintSwatch(paint: .solid(color), size: Theme.swatchPeek)
                case .gradient(let g, let kind): PaintSwatch(paint: .gradient(g, kind), size: Theme.swatchPeek)
                }
            }
            if entries.count > Self.peeked {
                Text("+\(entries.count - Self.peeked)")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.leading, Theme.space2)
            }
        }
        .padding(.trailing, Theme.panelPad - Theme.buttonInset)
    }

    // MARK: Colours

    private func colorRow(_ color: RGBA, places: [SelectionColors.Place]) -> some View {
        HStack(spacing: Theme.space6) {
            ColorWell(color: color, size: Theme.control, title: "Selection Colour",
                      onChange: { c in
                          if let command = SelectionColors.setting(places, to: c, in: controller.project) {
                              controller.update(command)
                          }
                      },
                      onBegin: { controller.begin("Selection Colour") },
                      onEnd: { controller.end() })
            HexField(color: color) { set(places, to: $0) }
            UnitField(value: color.a * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                var c = color
                c.a = v / 100
                set(places, to: c)
            }
            .frame(width: Theme.labelWidth)
            .help("Opacity of this colour, wherever it is used")
        }
        .help(usedIn(places))
    }

    private func set(_ places: [SelectionColors.Place], to color: RGBA) {
        guard let command = SelectionColors.setting(places, to: color, in: controller.project) else { return }
        controller.perform(command)
    }

    // MARK: Gradients

    @ViewBuilder
    private func gradientRows(_ gradient: MotionModel.Gradient, kind: GradientKind, entry: SelectionColors.Entry) -> some View {
        let isOpen = open == entry.id
        VStack(alignment: .leading, spacing: Theme.space8) {
            Button {
                pickedStop = nil
                open = isOpen ? nil : entry.id
            } label: {
                HStack(spacing: Theme.space6) {
                    PaintSwatch(paint: .gradient(gradient, kind))
                    Text(Paint.gradient(gradient, kind).kindName)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    IconView(isOpen ? .chevronUp : .chevronDown, size: Theme.iconSmall)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.trailing, Theme.space8)
                }
                .frame(height: Theme.control)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isOpen ? "Close this gradient's stops" : "Change this gradient's stops, \(usedIn(entry.places).lowercasedFirst)")
            if isOpen {
                let places = entry.places
                GradientStopsEditor(
                    gradient: gradient, title: "Selection Gradient", picked: pickedStop,
                    pick: { pickedStop = $0 },
                    edit: GradientCallbacks(
                        commit: { g in
                            if let command = SelectionColors.setting(places, toStopsOf: g, in: controller.project) {
                                controller.perform(command)
                            }
                        },
                        live: { g in
                            if let command = SelectionColors.setting(places, toStopsOf: g, in: controller.project) {
                                controller.update(command)
                            }
                        },
                        begin: { _ in controller.begin("Selection Gradient") },
                        end: { controller.end() }),
                    barButton: { EmptyView() })
            }
        }
        .onChange(of: entry.id) { _, _ in pickedStop = nil }
    }

    /// Where a colour is used, for its tooltip: how many layers, and how
    /// many actions follow it.
    private func usedIn(_ places: [SelectionColors.Place]) -> String {
        var layers = Set<UUID>(), actions = Set<UUID>()
        for place in places {
            switch place {
            case .fill(let l, _), .stroke(let l, _), .shadow(let l, _), .textColor(let l), .textStroke(let l): layers.insert(l)
            case .actionStart(let a), .actionEnd(let a): actions.insert(a)
            }
        }
        var text = "Used in \(layers.count) \(layers.count == 1 ? "layer" : "layers")"
        if !actions.isEmpty { text += " and \(actions.count) \(actions.count == 1 ? "action" : "actions")" }
        return text
    }
}

private extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
