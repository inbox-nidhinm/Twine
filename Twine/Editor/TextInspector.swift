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
///
/// It edits one text, or several selected together: every change goes to
/// all of them as one undo step, and what they do not share reads Mixed.
struct TextSection: View {
    let layers: [Layer]
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var fontFrame: CGRect = .zero
    @State private var settingsFrame: CGRect = .zero

    private var texts: [TextContent] { layers.compactMap(\.textContent) }
    /// The first text, whose values the fields start from.
    private var text: TextContent { texts[0] }

    var body: some View {
        if !texts.isEmpty { section }
    }

    private var section: some View {
        let weight = texts.shared(\.fontWeight)
        let sizing = texts.shared(\.sizing)
        return VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Text") {}
            VStack(alignment: .leading, spacing: 8) {
                fontButton
                HStack(spacing: 8) {
                    MenuField(value: weight.map(Self.weightName) ?? UnitField.mixedText, entries: weightEntries, height: Theme.control)
                        .help("The font's weight")
                    UnitField(value: text.fontSize, decimals: 1, suffix: "px", accepts: { $0 >= 1 && $0 <= 2000 },
                              mixed: texts.shared(\.fontSize) == nil) { v in
                        edit { $0.fontSize = v }
                    }
                    .frame(width: Theme.textSideColumn)
                    .help("Type size")
                }
                HStack(spacing: 8) {
                    alignmentTray
                    MenuField(value: sizing.map { $0 == .autoWidth ? "Auto" : "Fixed" } ?? UnitField.mixedText, entries: {
                        TextSizing.allCases.map { s in
                            .item(s == .autoWidth ? "Auto" : "Fixed", checked: s == sizing) {
                                edit { $0.sizing = s }
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
                        let ids = layers.map(\.id)
                        menus.showPopup(at: CGPoint(x: inspectorLeft - Theme.floatGap - Theme.cardWidth,
                                                    y: settingsFrame.minY - 40)) {
                            PopupCard(title: "Text", width: Theme.cardWidth) {
                                TextSpacingSettings(layerIDs: ids, controller: controller)
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
                           isOn: texts.shared(\.alignment) == a) { edit { $0.alignment = a } }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
    }

    /// The family, drawn in itself, opening the font list. A family this Mac
    /// does not have shows dimmed, and the text draws in the system font.
    private var fontButton: some View {
        let family = texts.shared(\.fontFamily)
        let installed = family.map(TextLayout.isInstalled) ?? true
        return Button {
            let x = fontFrame.minX - Theme.cardWidth - Theme.floatGap * 2
            menus.showPopup(at: CGPoint(x: x, y: fontFrame.minY - 40)) {
                FontList(current: family ?? "") { picked in
                    menus.dismiss()
                    edit { $0.fontFamily = picked }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(family ?? UnitField.mixedText)
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
        .help(installed ? "The font family" : "\(family ?? "") is not installed on this Mac, so the text shows in SF Pro.")
    }

    private func weightEntries() -> [MenuEntry] {
        stride(from: 100, through: 900, by: 100).map { w in
            .item("\(Self.weightName(w))   \(w)", checked: w == texts.shared(\.fontWeight)) { edit { $0.fontWeight = w } }
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

    private func edit(_ change: (inout TextContent) -> Void) {
        controller.editTexts(layers.map(\.id), change)
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
/// button. It reads the layers afresh, so it follows every edit while it is up.
private struct TextSpacingSettings: View {
    let layerIDs: [UUID]
    let controller: EditorController

    var body: some View {
        let texts = layerIDs.compactMap { controller.project.layer(withID: $0)?.textContent }
        if let text = texts.first {
            let lineMixed = Self.lineHeightsDiffer(texts)
            LabeledRow(label: "Letter") {
                UnitField(value: text.letterSpacing, decimals: 1, suffix: "px",
                          mixed: texts.shared(\.letterSpacing) == nil) { v in edit { $0.letterSpacing = v } }
            }
            .help("Letter spacing: extra space between letters, in pixels")
            LabeledRow(label: "Line") {
                OptionalField(value: lineMixed ? nil : text.lineHeight, placeholder: TextLayout.naturalLineHeight(TextStyle(text)),
                              decimals: 1, suffix: "px", accepts: { $0 > 0 }, mixed: lineMixed) { v in edit { $0.lineHeight = v } }
            }
            .help("Line height, baseline to baseline, in pixels. Empty uses the font's own.")
        }
    }

    private func edit(_ change: (inout TextContent) -> Void) {
        controller.editTexts(layerIDs, change)
    }

    /// Different line heights, or all the font's own but from fonts whose
    /// own heights differ.
    private static func lineHeightsDiffer(_ texts: [TextContent]) -> Bool {
        switch texts.shared(\.lineHeight) {
        case .none: return true
        case .some(.none): return texts.shared { TextLayout.naturalLineHeight(TextStyle($0)) } == nil
        case .some(.some): return false
        }
    }
}

// MARK: - Fill and stroke

/// A text's colour, as a shape's Fill: its well, hex and opacity, and
/// show or hide. A text always has one, so there is nothing to add.
///
/// For several texts it shows the first one's colour. A new colour goes to
/// all of them, keeping each one's own opacity, and a new opacity keeps each
/// one's own colour.
struct TextFillSection: View {
    let layers: [Layer]
    let controller: EditorController

    var body: some View {
        let texts = layers.compactMap(\.textContent)
        if let shown = texts.first?.color {
            let showing = texts.contains(where: \.showsFill)
            VStack(alignment: .leading, spacing: 8) {
                HeaderRow(title: "Fill") {}
                PaintEditor(paint: .solid(shown), isEnabled: showing, controller: controller, layer: layers[0],
                            title: "Fill",
                            change: { paint in
                                guard case .solid(let c) = paint else { return [] }
                                let sameColour = c.r == shown.r && c.g == shown.g && c.b == shown.b
                                return controller.freshLayers(layers.map(\.id)).map { l in
                                    l.editingText { t in
                                        if sameColour {
                                            t.color.a = c.a
                                        } else {
                                            t.color = RGBA(c.r, c.g, c.b, c.a == shown.a ? t.color.a : c.a)
                                        }
                                    }
                                }
                            },
                            toggle: { controller.editTexts(layers.map(\.id)) { $0.hidesFill = showing ? true : nil } },
                            showsToggle: true)
                    .gridBody()
            }
            .padding(.bottom, Theme.panelPad)
        }
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
                                change: { paint in [layer.editingText { if case .solid(let c) = paint { $0.stroke?.paint = .color(c) } }] },
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
        .sectionPadding(empty: text.stroke == nil)
    }

    static func color(of stroke: Stroke) -> RGBA {
        switch stroke.paint {
        case .solid(let c): return c
        case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g): return g.stops.first?.color ?? .black
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
    /// The text, for a text layer.
    var textContent: TextContent? {
        if case .text(let t) = content { return t }
        return nil
    }

    /// The layer with its text changed, for a text layer; itself otherwise.
    func editingText(_ change: (inout TextContent) -> Void) -> Layer {
        guard case .text(var t) = content else { return self }
        change(&t)
        var l = self
        l.content = .text(t)
        return l
    }
}

extension Collection {
    /// The value every element has, or nil when they differ or there are none.
    func shared<T: Equatable>(_ key: (Element) -> T) -> T? {
        guard let first = first.map(key) else { return nil }
        return allSatisfy { key($0) == first } ? first : nil
    }
}

extension EditorController {
    /// The layers as they are now in the project, in the order given.
    func freshLayers(_ ids: [UUID]) -> [Layer] { ids.compactMap { project.layer(withID: $0) } }

    /// Changes the text of each of these layers the same way, as one undo
    /// step: the Text and Fill sections, for one text or several.
    func editTexts(_ ids: [UUID], _ change: (inout TextContent) -> Void) {
        let edited = freshLayers(ids).filter(\.isText).map { $0.editingText(change) }
        guard !edited.isEmpty else { return }
        perform(layerUpdate(edited))
    }
}
