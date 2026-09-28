import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// A text layer as designed: its words, font, size, colour and setting. The
/// box follows the words; its width only holds when the layer is Fixed width.
struct TextSection: View {
    let layer: Layer
    let text: TextContent
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var fontFrame: CGRect = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Text") {}
            VStack(alignment: .leading, spacing: 8) {
                TextBox(layerID: layer.id, text: text.text, controller: controller)
                fontRow
                HStack(spacing: 8) {
                    MenuRow(label: "Weight", value: Self.weightName(text.fontWeight), entries: weightEntries)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Size")
                            .font(ThemeFont.label)
                            .foregroundStyle(Theme.textSecondary)
                        UnitField(value: text.fontSize, decimals: 1, suffix: "px", accepts: { $0 >= 1 && $0 <= 2000 }) { v in
                            edit { $0.fontSize = v }
                        }
                    }
                    .padding(.vertical, 2)
                }
                ColorRow(color: text.color, title: "Text", edit: EditCallbacks(
                    commit: { c in edit { $0.color = c } },
                    live: { c in controller.update([with { $0.color = c }]) },
                    begin: { controller.begin("Text Colour") },
                    end: { controller.end() }))
                SegmentRow(selection: text.alignment, options: MotionModel.TextAlignment.allCases, title: Self.alignmentTitle) { a in
                    edit { $0.alignment = a }
                }
                HStack(spacing: 8) {
                    UnitField(unit: "Letter", value: text.letterSpacing, decimals: 1) { v in edit { $0.letterSpacing = v } }
                        .help("Letter spacing: extra space between letters, in pixels")
                    OptionalField(unit: "Line", value: text.lineHeight, placeholder: natural, decimals: 1,
                                  accepts: { $0 > 0 }) { v in edit { $0.lineHeight = v } }
                        .help("Line height, baseline to baseline, in pixels. Empty uses the font's own.")
                }
                SegmentRow(selection: text.sizing, options: TextSizing.allCases,
                           title: { $0 == .autoWidth ? "Auto width" : "Fixed width" }) { sizing in
                    edit { $0.sizing = sizing }
                }
                .help("Auto width grows the box to fit each line. Fixed width keeps the box's width and wraps inside it.")
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }

    private var natural: Double { TextLayout.naturalLineHeight(TextStyle(text)) }

    /// The family, drawn in itself, opening the font list. A family this Mac
    /// does not have shows dimmed, and the text draws in the system font.
    private var fontRow: some View {
        let installed = TextLayout.isInstalled(text.fontFamily)
        return VStack(alignment: .leading, spacing: 6) {
            Text("Font")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Button {
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
                .frame(height: Theme.panelRow + 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fontFrame = $0 }
            .help(installed ? "The font family" : "\(text.fontFamily) is not installed on this Mac, so the text shows in SF Pro.")
        }
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

/// The words, typed. Every keystroke shows on the canvas at once, and one
/// visit to the box undoes as one step. The words can also be typed on the
/// canvas itself; this box follows along.
private struct TextBox: View {
    let layerID: UUID
    let text: String
    let controller: EditorController

    @State private var draft = ""
    @State private var editing = false
    @FocusState private var focused: Bool

    var body: some View {
        TextEditor(text: $draft)
            .font(ThemeFont.label)
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .padding(.horizontal, 4)
            .padding(.vertical, 5)
            .frame(minHeight: Theme.control * 2, maxHeight: Theme.control * 5)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
            .focusRing(focused)
            .onAppear { draft = text }
            .onChange(of: text) { _, now in if !focused { draft = now } }
            .onChange(of: draft) { _, now in
                guard focused, now != text else { return }
                if !editing {
                    editing = true
                    controller.begin("Edit Text")
                }
                guard let layer = controller.project.layer(withID: layerID), case .text(var t) = layer.content else { return }
                var l = layer
                l.name = EditorController.textName(renaming: l.name, from: t.text, to: now)
                t.text = now
                l.content = .text(t)
                controller.update([l])
            }
            .onChange(of: focused) { _, now in
                if !now && editing {
                    editing = false
                    controller.end()
                }
            }
            .onDisappear {
                if editing {
                    editing = false
                    controller.end()
                }
            }
            .help("The layer's words. Return starts a new line.")
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
