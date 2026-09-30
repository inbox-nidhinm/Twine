import SwiftUI
import Theme

/// Twine's own shortcuts, grouped by where they work, on a card over the
/// window (Help > Keyboard Shortcuts, ⌘/). Only the app's: Copy, Paste,
/// Undo and the like work as everywhere on the Mac and are left out.
struct ShortcutsCard: View {
    let dismiss: () -> Void

    private let columnWidth: CGFloat = 262
    private let pad: CGFloat = 18

    var body: some View {
        ZStack {
            Theme.badge
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Keyboard Shortcuts")
                        .font(ThemeFont.labelStrong)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    IconButton(icon: .close, help: "Close (Esc or ⌘/)", action: dismiss)
                }
                .padding(.leading, pad)
                .padding(.trailing, Theme.sheetCloseInset)
                .frame(height: Theme.sheetHeader)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.hairline) }

                ScrollView {
                    HStack(alignment: .top, spacing: pad) {
                        ForEach(Array(Self.columns.enumerated()), id: \.offset) { _, column in
                            VStack(alignment: .leading, spacing: 20) {
                                ForEach(column, id: \.title) { group in
                                    ShortcutGroupView(group: group)
                                }
                            }
                            .frame(width: columnWidth, alignment: .leading)
                        }
                    }
                    .padding(pad)
                }
                .frame(maxHeight: 560)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: columnWidth * CGFloat(Self.columns.count) + pad * CGFloat(Self.columns.count + 1))
            .floatingPanel()
            .onExitCommand(perform: dismiss)
        }
    }

    // MARK: The list

    struct Shortcut {
        let keys: [String]
        let what: String
    }

    struct Group {
        let title: String
        let items: [Shortcut]
    }

    private static func s(_ what: String, _ keys: String...) -> Shortcut { Shortcut(keys: keys, what: what) }

    static let columns: [[Group]] = [
        [
            Group(title: "Modes and tools", items: [
                s("Design or Animate", "M"),
                s("Select", "V"),
                s("Frame", "F"),
                s("Rectangle, ellipse, line", "R", "O", "L"),
                s("Polygon, star", "Y", "S"),
                s("Pen", "P"),
                s("Text", "T"),
                s("Type into a text layer", "Return"),
            ]),
            Group(title: "Points", items: [
                s("Edit a shape's points", "Return"),
                s("Finish a path, stop editing", "Esc"),
                s("Sharp or smooth point", "⌘", "click"),
                s("Pull out handles", "⌘", "drag"),
                s("Move one handle alone", "⌥", "drag"),
                s("Delete points", "⌫"),
            ]),
            Group(title: "Pictures", items: [
                s("Crop a picture", "double-click"),
                s("Finish cropping", "Esc"),
            ]),
            Group(title: "View", items: [
                s("Pan", "Space", "drag"),
                s("Zoom to fit, actual size", "⌘0", "⌥⌘0"),
                s("Zoom in, out", "⌘=", "⌘-"),
                s("Hide layers, inspector", "⌘1", "⌘2"),
                s("Full screen", "⌃⌘F"),
                s("Keyboard shortcuts", "⌘/"),
            ]),
        ],
        [
            Group(title: "On the canvas", items: [
                s("Keep to one axis, square", "⇧", "drag"),
                s("Duplicate as you drag", "⌥", "drag"),
                s("Place without snapping", "⌘", "drag"),
                s("Resize from the centre", "⌥", "handle"),
                s("Move the anchor", "⌘", "anchor"),
                s("Select inside a group", "⌘", "click"),
                s("Nudge 1 px, 10 px", "←→", "⇧←→"),
            ]),
            Group(title: "Arrange", items: [
                s("Align left, centres, right", "⌥A", "⌥H", "⌥D"),
                s("Align top, middles, bottom", "⌥W", "⌥V", "⌥S"),
                s("Distribute across, down", "⌃⌥H", "⌃⌥V"),
                s("Group", "⌘G"),
                s("Ungroup groups and frames", "⇧⌘G", "⌘⌫"),
                s("Frame selection", "⌥⌘G"),
                s("Forward, backward", "⌘]", "⌘["),
                s("To front, to back", "⌥⌘]", "⌥⌘["),
            ]),
        ],
        [
            Group(title: "Playback", items: [
                s("Play or pause", "Space"),
                s("Frame back, forward", ",", "."),
                s("Ten frames", "⇧,", "⇧."),
                s("Previous, next action edge", "⌥,", "⌥."),
                s("Start, end", "Home", "End"),
            ]),
            Group(title: "Timeline", items: [
                s("Add or take away an action", "⌘", "click"),
                s("Select the actions between", "⇧", "click"),
                s("Move actions a frame", "←→", "⇧←→"),
                s("Trim both ends", "⌥", "drag end"),
                s("Pan", "⌥", "drag"),
                s("Zoom", "⌘", "scroll"),
                s("Copy, paste easing", "⌥⌘C", "⌥⌘V"),
            ]),
            Group(title: "Project", items: [
                s("Import", "⌘I"),
                s("Export, current frame", "⌘E", "⇧⌘E"),
                s("Duplicate, rename layer", "⌘D", "⌘R"),
                s("Rename in the layers panel", "double-click"),
                s("Duplicate project", "⇧⌘S"),
                s("Home", "⇧⌘H"),
            ]),
        ],
    ]
}

private struct ShortcutGroupView: View {
    let group: ShortcutsCard.Group

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.title)
                .font(ThemeFont.caption)
                .foregroundStyle(Theme.textTertiary)
            ForEach(group.items, id: \.what) { item in
                HStack(spacing: 6) {
                    Text(item.what)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 4)
                    ForEach(item.keys, id: \.self) { key in KeyCap(key) }
                }
            }
        }
    }
}

/// One key, or a word for what the mouse does, on a small raised cap.
private struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    /// Mouse words read as words, not keys.
    private var isGesture: Bool { key.first?.isLowercase == true }

    var body: some View {
        Text(key)
            .font(isGesture ? ThemeFont.caption : ThemeFont.label)
            .foregroundStyle(isGesture ? Theme.textTertiary : Theme.textPrimary)
            .padding(.horizontal, isGesture ? 0 : 5)
            .frame(minWidth: isGesture ? 0 : 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(isGesture ? .clear : Theme.panelRaised))
    }
}
