import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// A text layer as designed: its font, weight, size, alignment and width,
/// with letter spacing and line height behind the settings button. Its
/// colour and outline are the Fill and Stroke sections below it. The words
/// are typed on the canvas. The box follows the words; its width only holds
/// when the layer is Fixed width.
struct TextSection: View {
    let layer: Layer
    let text: TextContent
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var fontFrame: CGRect = .zero
    @State private var settingsFrame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Text") {}
            VStack(alignment: .leading, spacing: 8) {
                fontButton
                HStack(spacing: 8) {
                    MenuField(value: Self.weightName(text.fontWeight), entries: weightEntries, height: Theme.control)
                        .help("The font's weight")
                    UnitField(value: text.fontSize, decimals: 1, suffix: "px", accepts: { $0 >= 1 && $0 <= 2000 }) { v in
                        edit { $0.fontSize = v }
                    }
                    .frame(width: Theme.textSideColumn)
                    .help("Type size")
                }
                HStack(spacing: 8) {
                    alignmentTray
                    MenuField(value: text.sizing == .autoWidth ? "Auto" : "Fixed", entries: {
                        TextSizing.allCases.map { sizing in
                            .item(sizing == .autoWidth ? "Auto" : "Fixed", checked: sizing == text.sizing) {
                                edit { $0.sizing = sizing }
                            }
                        }
                    }, height: Theme.control)
                    .frame(width: Theme.textSideColumn)
                    .help("Auto grows the box to fit each line. Fixed keeps the box's width and wraps inside it.")
                }
                .rowButton {
                    IconButton(icon: .settings, help: "Letter spacing and line height") {
                        // Beside the inspector, towards the canvas, level with the button.
                        let inspectorLeft = settingsFrame.maxX + Theme.panelPad - Theme.panelWidth
                        menus.showPopup(at: CGPoint(x: inspectorLeft - Theme.floatGap - Theme.cardWidth,
                                                    y: settingsFrame.minY - 40)) {
                            PopupCard(title: "Text", width: Theme.cardWidth) {
                                TextSpacingSettings(layerID: layer.id, controller: controller)
                            }
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { settingsFrame = $0 }
                }
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }

    /// Left, centre and right. Justified text, from older files, shows none
    /// of them chosen.
    private var alignmentTray: some View {
        HStack(spacing: 1) {
            ForEach([MotionModel.TextAlignment.left, .center, .right], id: \.self) { a in
                TrayButton(icon: Self.alignmentIcon(a), help: "Align \(Self.alignmentTitle(a).lowercased())",
                           isOn: text.alignment == a) { edit { $0.alignment = a } }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
    }

    /// The family, drawn in itself, opening the font list. A family this Mac
    /// does not have shows dimmed, and the text draws in the system font.
    private var fontButton: some View {
        let installed = TextLayout.isInstalled(text.fontFamily)
        return Button {
            let x = fontFrame.minX - Theme.cardWidth - Theme.floatGap * 2
            menus.showPopup(at: CGPoint(x: x, y: fontFrame.minY - 40)) {
                FontList(current: text.fontFamily) { family in
                    menus.dismiss()
                    edit { $0.fontFamily = family }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(text.fontFamily)
                    .font(ThemeFont.label)
                    .foregroundStyle(installed ? Theme.textPrimary : Theme.textTertiary)
                    .strikethrough(!installed)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconView(.chevronDown, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: Theme.control)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fontFrame = $0 }
        .help(installed ? "The font family" : "\(text.fontFamily) is not installed on this Mac, so the text shows in SF Pro.")
    }

    private func weightEntries() -> [MenuEntry] {
        stride(from: 100, through: 900, by: 100).map { w in
            .item("\(Self.weightName(w))   \(w)", checked: w == text.fontWeight) { edit { $0.fontWeight = w } }
        }
    }

    static func weightName(_ weight: Int) -> String {
        switch weight {
        case ..<150: return "Thin"
        case ..<250: return "Extra Light"
        case ..<350: return "Light"
        case ..<450: return "Regular"
        case ..<550: return "Medium"
        case ..<650: return "Semibold"
        case ..<750: return "Bold"
        case ..<850: return "Extra Bold"
        default: return "Black"
        }
    }

    static func alignmentIcon(_ a: MotionModel.TextAlignment) -> Icon {
        switch a {
        case .left, .justified: return .textAlignLeft
        case .center: return .textAlignCenter
        case .right: return .textAlignRight
        }
    }

    static func alignmentTitle(_ a: MotionModel.TextAlignment) -> String {
        switch a {
        case .left: return "Left"
        case .center: return "Centre"
        case .right: return "Right"
        case .justified: return "Justify"
        }
    }

    private func with(_ change: (inout TextContent) -> Void) -> Layer {
        var l = layer
        var t = text
        change(&t)
        l.content = .text(t)
        return l
    }

    private func edit(_ change: (inout TextContent) -> Void) {
        let edited = with(change)
        controller.edit(layer.id) { $0 = edited }
    }
}

/// Every font family on this Mac, each shown in itself, with a search box.
private struct FontList: View {
    let current: String
    let pick: (String) -> Void

    @State private var search = ""
    @FocusState private var searching: Bool
    private let families = [TextLayout.systemFamily] + TextLayout.installedFamilies
        .filter { !$0.hasPrefix(".") }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    var body: some View {
        PopupCard(title: "Font", width: Theme.cardWidth) {
            TextField("Search", text: $search)
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .focused($searching)
                .padding(.horizontal, 8)
                .frame(height: Theme.control)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                .focusRing(searching)
                .onAppear { searching = true }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(shown, id: \.self) { family in
                        FontRow(family: family, isCurrent: family.caseInsensitiveCompare(current) == .orderedSame) {
                            pick(family)
                        }
                    }
                }
            }
            .frame(height: Theme.control * 12)
        }
    }

    private var shown: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? families : families.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}

private struct FontRow: View {
    let family: String
    let isCurrent: Bool
    let pick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            HStack(spacing: 6) {
                IconView(.check, size: 13)
                    .opacity(isCurrent ? 1 : 0)
                Text(family)
                    .font(family == TextLayout.systemFamily ? .system(size: 13) : .custom(family, size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 6)
            .frame(height: Theme.control)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(hovering ? Theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Letter spacing and line height, raised from the Text section's settings
/// button. It reads the layer afresh, so it follows every edit while it is up.
private struct TextSpacingSettings: View {
    let layerID: UUID
    let controller: EditorController

    var body: some View {
        if let layer = controller.project.layer(withID: layerID), case .text(let text) = layer.content {
            LabeledRow(label: "Letter") {
                UnitField(value: text.letterSpacing, decimals: 1, suffix: "px") { v in edit { $0.letterSpacing = v } }
            }
            .help("Letter spacing: extra space between letters, in pixels")
            LabeledRow(label: "Line") {
                OptionalField(value: text.lineHeight, placeholder: TextLayout.naturalLineHeight(TextStyle(text)), decimals: 1,
                              suffix: "px", accepts: { $0 > 0 }) { v in edit { $0.lineHeight = v } }
            }
            .help("Line height, baseline to baseline, in pixels. Empty uses the font's own.")
        }
    }

    private func edit(_ change: @escaping (inout TextContent) -> Void) {
        controller.edit(layerID) { l in
            guard case .text(var t) = l.content else { return }
            change(&t)
            l.content = .text(t)
        }
    }
}

// MARK: - Fill and stroke

/// A text's colour, as a shape's Fill: its well, hex and opacity, and
/// show or hide. A text always has one, so there is nothing to add.
struct TextFillSection: View {
    let layer: Layer
    let text: TextContent
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Fill") {}
            PaintEditor(paint: .solid(text.color), isEnabled: text.showsFill, controller: controller, layer: layer,
                        title: "Fill",
                        change: { paint in layer.editingText { if case .solid(let c) = paint { $0.color = c } } },
                        toggle: { controller.edit(layer.id) { l in l = l.editingText { $0.hidesFill = $0.showsFill ? true : nil } } },
                        showsToggle: true)
                .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }
}

/// An outline round the letters, as a shape's Stroke: its colour, where it
/// sits on the letters' edges, its width, and its corners behind the
/// settings button.
struct TextStrokeSection: View {
    let layer: Layer
    let text: TextContent
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var settingsFrame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Stroke") {
                if text.stroke == nil {
                    IconButton(icon: .plus, help: "Add a stroke") {
                        edit { $0.stroke = Stroke(paint: .color(LayerFactory.defaultStroke), width: 2) }
                    }
                } else {
                    IconButton(icon: .minus, help: "Remove the stroke") { edit { $0.stroke = nil } }
                }
            }
            if let stroke = text.stroke {
                VStack(alignment: .leading, spacing: 8) {
                    PaintEditor(paint: .solid(Self.color(of: stroke)), isEnabled: stroke.isEnabled, controller: controller,
                                layer: layer, title: "Stroke",
                                change: { paint in layer.editingText { if case .solid(let c) = paint { $0.stroke?.paint = .color(c) } } },
                                toggle: { edit { $0.stroke?.isEnabled.toggle() } },
                                showsToggle: true)
                    HStack(spacing: 8) {
                        MenuField(value: stroke.alignment.rawValue.capitalized, entries: {
                            StrokeAlignment.allCases.map { a in
                                .item(a.rawValue.capitalized, checked: a == stroke.alignment) { edit { $0.stroke?.alignment = a } }
                            }
                        }, height: Theme.control)
                        .help("Whether the stroke sits centred on the letters' edges, inside them, or outside them")
                        UnitField(value: stroke.width, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                            edit { $0.stroke?.width = v }
                        }
                        .help("Stroke width")
                    }
                    .rowButton {
                        IconButton(icon: .settings, help: "More stroke settings: corners") {
                            let inspectorLeft = settingsFrame.maxX + Theme.panelPad - Theme.panelWidth
                            menus.showPopup(at: CGPoint(x: inspectorLeft - Theme.floatGap - Theme.cardWidth,
                                                        y: settingsFrame.minY - 40)) {
                                PopupCard(title: "Stroke", width: Theme.cardWidth) {
                                    TextStrokeSettings(layerID: layer.id, controller: controller)
                                }
                            }
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { settingsFrame = $0 }
                    }
                }
                .gridBody()
            }
        }
        .padding(.bottom, Theme.panelPad)
    }

    static func color(of stroke: Stroke) -> RGBA {
        switch stroke.paint {
        case .solid(let c): return c
        case .linearGradient(let g), .radialGradient(let g): return g.stops.first?.color ?? .black
        case .image: return .black
        }
    }

    private func edit(_ change: (inout TextContent) -> Void) {
        let edited = layer.editingText(change)
        controller.edit(layer.id) { $0 = edited }
    }
}

/// How a text's stroke turns the letters' corners. It reads the layer
/// afresh, so it follows every edit while it is up.
private struct TextStrokeSettings: View {
    let layerID: UUID
    let controller: EditorController

    var body: some View {
        if let layer = controller.project.layer(withID: layerID), case .text(let text) = layer.content, let stroke = text.stroke {
            VStack(alignment: .leading, spacing: 6) {
                Text("Corners")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                SegmentRow(selection: stroke.join, options: LineJoin.allCases, title: { $0.rawValue.capitalized }) { j in
                    controller.edit(layerID) { l in l = l.editingText { $0.stroke?.join = j } }
                }
            }
            .help("How the stroke turns a corner")
        }
    }
}

extension Layer {
    /// The layer with its text changed, for a text layer; itself otherwise.
    func editingText(_ change: (inout TextContent) -> Void) -> Layer {
        guard case .text(var t) = content else { return self }
        change(&t)
        var l = self
        l.content = .text(t)
        return l
    }
}
