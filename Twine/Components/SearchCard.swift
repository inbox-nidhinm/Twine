import SwiftUI
import AppKit
import MotionEditing
import Theme

/// One thing the ⌘K card can find: a project, an action, a menu command.
struct SearchItem: Identifiable {
    /// The same every time the card opens, so Recent can find it again:
    /// `action.move`, `menu.Edit.Group`, a project's path.
    let id: String
    let title: String
    /// What sort of thing it is, at the row's right: Action, Preset, Layer.
    var kind: String
    /// After the title, dim: the group a layer is in, a project's folder.
    var detail: String? = nil
    var icon: Icon? = nil
    var thumbnail: NSImage? = nil
    /// In a picture's place when there is none: a project's ground.
    var swatch: Color? = nil
    var shortcut: String? = nil
    /// A setting that is on, or the tool in hand.
    var isOn = false
    /// Other words it is found by.
    var keywords: [String] = []
    /// Listed only once something is typed: layers, and projects past the
    /// latest few, of which there can be thousands.
    var onlyWhenSearching = false
    /// What Return does.
    var run: (@MainActor () -> Void)? = nil
    /// More to do with it, shown on Tab or its arrow: a project's Rename,
    /// Duplicate, Move to.
    var more: (@MainActor () -> [SearchItem])? = nil
    /// Return asks for a name instead, with this prompt and starting text,
    /// and hands it over.
    var naming: (prompt: String, initial: String, commit: @MainActor (String) -> Void)? = nil
}

/// A heading and what is under it, for the card with nothing typed.
struct SearchSection {
    let title: String
    let items: [SearchItem]
}

/// What a window offers the card, gathered as it opens, while the canvas
/// still has the keyboard, so menu commands are judged as the menus would.
struct SearchSource {
    var sections: [SearchSection]
    /// What the typed words ask for directly: a time to go to, a value to set.
    var typed: @MainActor (String) -> [SearchItem] = { _ in [] }
    /// Where the window's Recent list is kept.
    var recentsKey: String

    var items: [SearchItem] { sections.flatMap(\.items) }
}

/// The ⌘K card: a search box over the window, with what matches under it.
/// Up and Down pick, Return does it, Tab shows more about it, Escape goes
/// back a step or closes.
struct SearchCard: View {
    let source: SearchSource
    let close: () -> Void

    private enum Step {
        case more(title: String, items: [SearchItem])
        case naming(prompt: String, commit: @MainActor (String) -> Void)
    }

    @State private var query = ""
    @State private var highlighted = 0
    @State private var steps: [Step] = []
    /// Where the pointer last was, so a row moving under a still pointer as
    /// the list scrolls does not take the highlight from the keyboard.
    @State private var pointer: CGPoint?
    @FocusState private var focused: Bool

    /// How many matches show at most.
    private static let shown = 60
    private static let recentCount = 6

    var body: some View {
        ZStack(alignment: .top) {
            // A click anywhere else puts the card away.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            VStack(spacing: 0) {
                field
                if !isNaming {
                    Rectangle().fill(Theme.border).frame(height: Theme.hairline)
                    list
                }
            }
            .frame(width: Theme.searchWidth)
            .floatingPanel()
            .padding(.top, Theme.searchTop)
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    // MARK: The search box

    private var field: some View {
        HStack(spacing: 10) {
            IconView(isNaming ? .text : .search, size: 18)
                .foregroundStyle(Theme.textTertiary)
            if let title = stepTitle {
                Text(title)
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(height: Theme.control - 4)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(Theme.panelRaised))
                    .fixedSize()
            }
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(ThemeFont.search)
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit(submit)
                .onChange(of: query) { _, _ in highlighted = 0 }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.tab) {
                    guard choices.indices.contains(highlighted), choices[highlighted].more != nil else { return .ignored }
                    showMore(choices[highlighted])
                    return .handled
                }
                .onKeyPress(.delete) {
                    guard query.isEmpty, !steps.isEmpty else { return .ignored }
                    back()
                    return .handled
                }
                .onKeyPress(.escape) {
                    back()
                    return .handled
                }
                .onExitCommand(perform: back)
        }
        .padding(.horizontal, Theme.panelPad + 2)
        .frame(height: Theme.searchField)
    }

    private var isNaming: Bool { if case .naming = steps.last { true } else { false } }

    private var stepTitle: String? {
        switch steps.last {
        case .more(let title, _)?: title
        case .naming(let prompt, _)?: prompt
        case nil: nil
        }
    }

    private var placeholder: String { isNaming ? "Name" : "Search" }

    // MARK: The list

    /// What shows, under headings: with nothing typed, Recent and then each
    /// section; with something typed, what it asks for directly and then
    /// the matches, best first.
    private var groups: [(title: String?, items: [SearchItem])] {
        let items: [SearchItem]
        switch steps.last {
        case .more(_, let more)?: items = more
        case .naming?: return []
        case nil: items = source.items
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            guard steps.isEmpty else { return [(nil, items)] }
            var out: [(String?, [SearchItem])] = []
            let recent = SearchRecents.ids(source.recentsKey).compactMap { id in items.first { $0.id == id } }
            if !recent.isEmpty { out.append(("Recent", Array(recent.prefix(Self.recentCount)))) }
            for section in source.sections {
                let shown = section.items.filter { !$0.onlyWhenSearching }
                if !shown.isEmpty { out.append((section.title, shown)) }
            }
            return out
        }
        let recent = steps.isEmpty ? SearchRecents.ids(source.recentsKey) : []
        let matches = items.enumerated().compactMap { i, item -> (SearchItem, Double, Int)? in
            guard var score = SearchMatch.score(q, in: item.title, keywords: item.keywords + [item.detail ?? ""].filter { !$0.isEmpty })
            else { return nil }
            // What was chosen lately counts for a little more.
            if let r = recent.firstIndex(of: item.id) { score += 4 - Double(r) * 0.5 }
            return (item, score, i)
        }
        .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
        .prefix(Self.shown)
        .map(\.0)
        let typed = steps.isEmpty ? source.typed(q) : []
        return [(nil, typed), (nil, Array(matches))].filter { !$0.1.isEmpty }
    }

    private var choices: [SearchItem] { groups.flatMap(\.items) }

    private var list: some View {
        let groups = self.groups
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if groups.isEmpty {
                        Text("No results")
                            .font(ThemeFont.searchResult)
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, Theme.panelPad + 2)
                            .frame(height: Theme.searchRow)
                    }
                    let starts = groups.indices.map { g in groups[..<g].reduce(0) { $0 + $1.items.count } }
                    ForEach(groups.indices, id: \.self) { g in
                        if let title = groups[g].title {
                            Text(title)
                                .font(ThemeFont.caption)
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, Theme.panelPad + 2)
                                .frame(height: Theme.control, alignment: .bottomLeading)
                                .padding(.top, g == 0 ? 0 : Theme.rowGap)
                        }
                        ForEach(groups[g].items.indices, id: \.self) { i in
                            let index = starts[g] + i
                            row(groups[g].items[i], index: index).id(index)
                        }
                    }
                }
                .padding(.vertical, Theme.menuPad)
            }
            .frame(maxHeight: Theme.searchList)
            .fixedSize(horizontal: false, vertical: true)
            .onChange(of: highlighted) { _, now in proxy.scrollTo(now) }
        }
    }

    private func row(_ item: SearchItem, index: Int) -> some View {
        let lit = index == highlighted
        return ZStack(alignment: .trailing) {
            Button { choose(item) } label: {
                HStack(spacing: 10) {
                    if let thumbnail = item.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Theme.searchThumb.width, height: Theme.searchThumb.height)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSwatchMark))
                    } else if let swatch = item.swatch {
                        RoundedRectangle(cornerRadius: Theme.radiusSwatchMark)
                            .fill(swatch)
                            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSwatchMark).strokeBorder(Theme.edge, lineWidth: 1))
                            .frame(width: Theme.searchThumb.width, height: Theme.searchThumb.height)
                    } else {
                        Group {
                            if let icon = item.icon { IconView(icon, size: 16) } else { Color.clear }
                        }
                        .frame(width: Theme.searchThumb.width, height: Theme.searchThumb.height)
                        .foregroundStyle(lit ? Theme.textPrimary : Theme.textSecondary)
                    }
                    Text(item.title)
                        .font(ThemeFont.searchResult)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(ThemeFont.searchResult)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    if item.isOn {
                        IconView(.check, size: 13).foregroundStyle(Theme.textSecondary)
                    }
                    if let shortcut = item.shortcut {
                        Text(shortcut)
                            .font(ThemeFont.label)
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                    }
                    Text(item.kind)
                        .font(ThemeFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                    // Room for the arrow laid over the row's end.
                    if item.more != nil { Color.clear.frame(width: Theme.control) }
                }
                .padding(.horizontal, Theme.panelPad - Theme.menuPad + 2)
                .frame(height: Theme.searchRow)
                .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(lit ? Theme.rowSelected : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if item.more != nil {
                Button { showMore(item) } label: {
                    IconView(.chevronRight, size: 14)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: Theme.control, height: Theme.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, Theme.panelPad - Theme.menuPad - 2)
                .help("More (Tab)")
            }
        }
        .padding(.horizontal, Theme.menuPad)
        .onContinuousHover(coordinateSpace: .global) { phase in
            guard case .active(let p) = phase else { return }
            if let pointer, pointer != p { highlighted = index }
            pointer = p
        }
    }

    // MARK: Choosing

    private func move(_ by: Int) -> KeyPress.Result {
        let count = choices.count
        guard count > 0 else { return .handled }
        highlighted = (highlighted + by + count) % count
        return .handled
    }

    private func submit() {
        if case .naming(_, let commit)? = steps.last {
            let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return NSSound.beep() }
            close()
            DispatchQueue.main.async { commit(name) }
            return
        }
        guard choices.indices.contains(highlighted) else { return NSSound.beep() }
        choose(choices[highlighted])
    }

    private func choose(_ item: SearchItem) {
        // Only what Recent can list again: not a typed value, nor a step in.
        if steps.isEmpty, source.items.contains(where: { $0.id == item.id }) {
            SearchRecents.remember(item.id, in: source.recentsKey)
        }
        if let naming = item.naming {
            steps.append(.naming(prompt: naming.prompt, commit: naming.commit))
            query = naming.initial
        } else if let run = item.run {
            close()
            // Once the card has gone and the keyboard is back where it was.
            DispatchQueue.main.async { run() }
        } else if item.more != nil {
            showMore(item)
        }
    }

    private func showMore(_ item: SearchItem) {
        guard let more = item.more else { return }
        steps.append(.more(title: item.title, items: more()))
        query = ""
        highlighted = 0
    }

    /// Escape: back a step, or away.
    private func back() {
        guard !steps.isEmpty else { return close() }
        steps.removeLast()
        query = ""
        highlighted = 0
    }
}

/// What was chosen lately from each window's card, newest first.
enum SearchRecents {
    private static let kept = 12

    static func ids(_ key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func remember(_ id: String, in key: String) {
        var list = ids(key).filter { $0 != id }
        list.insert(id, at: 0)
        UserDefaults.standard.set(Array(list.prefix(kept)), forKey: key)
    }
}

extension MainMenu {
    /// The menu bar's commands that can run now, as the card lists them:
    /// judged by the menus' own checks at this moment, named as the menus
    /// name them (dropping the keys written into some titles, which become
    /// the shortcut), each run by sending its menu item's action as a click
    /// on it would. The Window menu, the app menu's system items and Close
    /// (which in one window quits) are left out, as is anything in `except`.
    @MainActor
    static func searchSections(except: Set<Selector> = []) -> [SearchSection] {
        guard let bar = NSApp.mainMenu else { return [] }
        let skipped: Set<Selector> = except.union([
            #selector(EditorWindowController.showSearch(_:)), #selector(NSWindow.performClose(_:)),
            #selector(NSApplication.orderFrontStandardAboutPanel(_:)), #selector(NSApplication.hide(_:)),
            #selector(NSApplication.hideOtherApplications(_:)), #selector(NSApplication.unhideAllApplications(_:)),
            #selector(NSApplication.terminate(_:)),
            // What macOS adds to the Edit menu by itself.
            #selector(NSApplication.orderFrontCharacterPalette(_:)), Selector(("startDictation:")),
        ])
        var sections: [SearchSection] = []
        for top in bar.items {
            guard let menu = top.submenu, menu !== NSApp.windowsMenu else { continue }
            menu.update()
            let items = menu.items.compactMap { entry -> SearchItem? in
                guard let action = entry.action, !skipped.contains(action), entry.isEnabled, !entry.isHidden, !entry.isAlternate,
                      entry.submenu == nil, !NSStringFromSelector(action).lowercased().contains("autofill") else { return nil }
                let parts = entry.title.components(separatedBy: "    ")
                let title = renamed["\(menu.title)/\(parts[0])"] ?? parts[0]
                let written = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : nil
                return SearchItem(id: "menu.\(menu.title).\(NSStringFromSelector(action)).\(entry.tag)",
                                  title: title, kind: menu.title, shortcut: written ?? shortcut(of: entry),
                                  isOn: entry.state == .on, keywords: keywords[parts[0]] ?? [], run: { [weak entry] in
                    guard let entry else { return }
                    NSApp.sendAction(action, to: entry.target, from: entry)
                })
            }
            if !items.isEmpty { sections.append(SearchSection(title: menu.title, items: items)) }
        }
        // The menus in the order the card lists them: editing first.
        let order = ["Edit", "Arrange", "View", "Playback", "File", "Help", "Twine"]
        return sections.sorted { (order.firstIndex(of: $0.title) ?? order.count) < (order.firstIndex(of: $1.title) ?? order.count) }
    }

    /// Menu items whose name only reads plainly in their menu.
    private static let renamed: [String: String] = [
        "File/Duplicate": "Duplicate Project",
        "File/Rename…": "Rename Project…",
        "File/Move To…": "Move Project To…",
        "File/Revert To…": "Revert Project To…",
        "File/Save": "Save Project",
        "File/Show in Finder": "Show Project in Finder",
    ]

    /// Other words people search by.
    private static let keywords: [String: [String]] = [
        "Smart Guides": ["snapping", "snap"],
        "Use as Mask": ["mask", "clip"],
        "Zoom to Fit": ["fit"],
        "Export…": ["render", "movie", "video", "gif", "save as"],
        "Export Current Frame…": ["png", "still", "image"],
        "Import…": ["media", "picture", "image", "video", "sound", "svg"],
        "Keyboard Shortcuts": ["keys", "shortcuts"],
        "Play or Pause": ["play", "pause"],
        "Play": ["play", "pause"],
        "Pause": ["play", "pause"],
        "Hide Layers": ["layers panel"],
        "Show Layers": ["layers panel"],
        "Hide Inspector": ["inspector panel"],
        "Show Inspector": ["inspector panel"],
        "Frame Selection": ["frame"],
        "Group": ["group"],
        "Stagger Actions…": ["offset", "cascade"],
    ]

    /// A menu item's key, as the menu draws it: ⇧⌘G.
    private static func shortcut(of entry: NSMenuItem) -> String? {
        guard !entry.keyEquivalent.isEmpty else { return nil }
        let m = entry.keyEquivalentModifierMask
        var out = ""
        if m.contains(.control) { out += "⌃" }
        if m.contains(.option) { out += "⌥" }
        if m.contains(.shift) || entry.keyEquivalent != entry.keyEquivalent.lowercased() { out += "⇧" }
        if m.contains(.command) { out += "⌘" }
        return out + entry.keyEquivalent.uppercased()
    }
}
