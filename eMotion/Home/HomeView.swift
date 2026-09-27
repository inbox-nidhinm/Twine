import SwiftUI
import AppKit
import MotionModel
import Theme

/// What the app opens onto: every project in `eMotion Creations`, as a shelf,
/// with its folders down the sidebar. Cards drag onto a folder, or onto All
/// Projects to come out of one.
struct HomeView: View {
    @Bindable var library: Library

    @Environment(MenuHost.self) private var menus
    @State private var hovered: URL?
    @State private var renaming: URL?
    @State private var draft = ""
    @FocusState private var renameFocused: Bool
    /// The folder being named in the sidebar.
    @State private var renamingFolder: URL?
    @State private var folderDraft = ""
    @FocusState private var folderFocused: Bool
    /// The sidebar row a card is being dragged over: a folder, or the
    /// creations folder itself for All Projects.
    @State private var dropTarget: URL?

    /// 216 plus the float inset either side is `panelWidth`, the column the
    /// editor's layers panel takes, so the two screens share a left edge.
    private let sidebar: CGFloat = Theme.panelWidth - Theme.floatInset * 2
    /// Where the rule under both titles lands from the top of the window.
    /// Shared, so the wordmark and the shelf title sit on one line.
    private let titleBlock: CGFloat = 94
    private let card: CGFloat = 158
    private let cardPad: CGFloat = 5
    private let cardFoot: CGFloat = 12
    private let gutter: CGFloat = 24
    private let margin: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            shelf
        }
        .background(Theme.canvas.grained())
        // The app's arrow everywhere, never the system's.
        .background(CursorArea())
        .overlay {
            if library.showVersionHistory {
                VersionHistoryCard { library.showVersionHistory = false }
                    .transition(.opacity)
            }
        }
        .overlay { MenuLayer() }
        .animation(.easeOut(duration: 0.14), value: library.showVersionHistory)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    // MARK: Sidebar

    private var sidebarColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Twine")
                .displayTitle(24)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.panelPad)
                .padding(.bottom, 12)
                .frame(height: titleBlock - Theme.floatInset, alignment: .bottomLeading)
            PanelDivider()
            sidebarRow("All Projects", selected: library.selectedFolder == nil) { library.selectedFolder = nil }
                .background(dropHighlight(Creations.folder.standardizedFileURL))
                .dropDestination(for: URL.self) { urls, _ in drop(urls, into: nil) } isTargeted: {
                    target(Creations.folder.standardizedFileURL, $0)
                }
                .padding(.top, Theme.rowGap * 2)
            foldersSection
            Spacer(minLength: 0)
            PanelDivider()
            sidebarRow("Version History", trailing: "Build \(VersionHistory.version)", selected: false) {
                library.showVersionHistory = true
            }
            .padding(.vertical, Theme.rowGap * 2)
        }
        .frame(width: sidebar)
        .frame(maxHeight: .infinity)
        .floatingPanel()
        .padding(Theme.floatInset)
    }

    private func sidebarRow(_ title: String, icon: Icon? = nil, trailing: String? = nil, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        SidebarRow(title: title, icon: icon, trailing: trailing, selected: selected, action: action)
    }

    // MARK: Folders

    private var foldersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Folders")
                    .font(ThemeFont.labelStrong)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                IconButton(icon: .plus, help: "New Folder") {
                    if let url = library.newFolder() {
                        library.selectedFolder = url
                        folderDraft = url.lastPathComponent
                        renamingFolder = url
                    }
                }
            }
            .padding(.leading, Theme.panelPad)
            .padding(.trailing, Theme.panelPad - 6)
            .frame(height: Theme.listRow)
            .padding(.top, Theme.rowGap * 2)
            ForEach(library.folders) { folder in folderRow(folder) }
        }
    }

    @ViewBuilder private func folderRow(_ folder: Library.Folder) -> some View {
        if renamingFolder == folder.url {
            HStack(spacing: 6) {
                IconView(.folder, size: 16)
                    .foregroundStyle(Theme.textSecondary)
                TextField("", text: $folderDraft)
                    .textFieldStyle(.plain)
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($folderFocused)
                    .onAppear { DispatchQueue.main.async { folderFocused = true } }
                    .onSubmit { commitFolderRename(folder) }
                    .onExitCommand { renamingFolder = nil }
                    .onChange(of: folderFocused) { _, now in if !now, renamingFolder == folder.url { commitFolderRename(folder) } }
            }
            .padding(.horizontal, Theme.panelPad - 4)
            .frame(height: Theme.listRow)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(Theme.rowSelected))
            .padding(.horizontal, 4)
        } else {
            sidebarRow(folder.name, icon: .folder, trailing: "\(library.count(in: folder))",
                       selected: library.selectedFolder == folder.url) {
                library.selectedFolder = folder.url
            }
            .background(dropHighlight(folder.url))
            .dropDestination(for: URL.self) { urls, _ in drop(urls, into: folder.url) } isTargeted: {
                target(folder.url, $0)
            }
            .rightClickMenu {
                [
                    .item("Rename") {
                        folderDraft = folder.name
                        renamingFolder = folder.url
                    },
                    .item("Show in Finder") { library.reveal(folder) },
                    .separator,
                    .item("Move to Trash") { library.moveToTrash(folder) },
                ]
            }
        }
    }

    private func commitFolderRename(_ folder: Library.Folder) {
        renamingFolder = nil
        library.rename(folder, to: folderDraft)
    }

    /// A row lights up while a card is held over it.
    private func dropHighlight(_ url: URL) -> some View {
        RoundedRectangle(cornerRadius: Theme.radiusRow)
            .strokeBorder(Theme.accent, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(Theme.rowCurrent))
            .padding(.horizontal, 4)
            .opacity(dropTarget == url ? 1 : 0)
    }

    private func target(_ url: URL, _ over: Bool) {
        if over { dropTarget = url } else if dropTarget == url { dropTarget = nil }
    }

    /// Cards dropped on a folder go into it; on All Projects, out of theirs.
    private func drop(_ urls: [URL], into folder: URL?) -> Bool {
        dropTarget = nil
        let projects = urls.map(\.standardizedFileURL).filter(library.isProject)
        guard !projects.isEmpty else { return false }
        for url in projects { library.move(url, to: folder) }
        return true
    }

    // MARK: Shelf

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                Text(library.folders.first { $0.url == library.selectedFolder }?.name ?? "All Projects")
                    .displayTitle(24)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                PanelButton(title: "New Project", icon: .plus) { library.newProject() }
                    .fixedSize()
                    .help("New Project (⌘N)")
            }
            .padding(.horizontal, margin)
            .padding(.bottom, 12)
            .frame(height: titleBlock, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())

            Rectangle().fill(Theme.border).frame(height: 1).padding(.horizontal, margin)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: card, maximum: card), spacing: gutter,
                                             alignment: .topLeading)],
                          alignment: .leading, spacing: gutter) {
                    ForEach(library.shownItems) { item in projectCard(item) }
                }
                .padding(margin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func projectCard(_ item: Library.Item) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ProjectThumbnail(item: item)
                .frame(height: (card - cardPad * 2) * 0.625)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusWell - 2))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusWell - 2).strokeBorder(Theme.edge, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                if renaming == item.url {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .focused($renameFocused)
                        .onAppear { DispatchQueue.main.async { renameFocused = true } }
                        .onSubmit { commitRename(item) }
                        .onExitCommand { renaming = nil }
                        .onChange(of: renameFocused) { _, now in if !now, renaming == item.url { commitRename(item) } }
                } else {
                    Text(item.name)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                // In All Projects a card says which folder it is in.
                Text([library.selectedFolder == nil ? item.folder?.lastPathComponent : nil,
                      item.modified.formatted(date: .abbreviated, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                    .font(ThemeFont.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 3)
            .padding(.top, 8)
        }
        .padding(cardPad)
        .padding(.bottom, cardFoot - cardPad)
        .frame(width: card)
        .background(RoundedRectangle(cornerRadius: Theme.radiusWell)
            .fill(hovered == item.url ? Theme.panelRaised : Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusWell).strokeBorder(Theme.border, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? item.url : (hovered == item.url ? nil : hovered) }
        .onTapGesture { if renaming != item.url { library.open(item) } }
        .draggable(item.url)
        .rightClickMenu {
            [
                .item("Open") { library.open(item) },
                .item("Rename") {
                    draft = item.name
                    renaming = item.url
                },
                .item("Duplicate") { library.duplicate(item) },
                .item("Show in Finder") { library.reveal(item) },
            ] + moveEntries(item) + [
                .separator,
                .item("Move to Trash") { library.moveToTrash(item) },
            ]
        }
    }

    /// Move to: each folder, and out of the one it is in.
    private func moveEntries(_ item: Library.Item) -> [MenuEntry] {
        guard !library.folders.isEmpty else { return [] }
        var entries: [MenuEntry] = [.separator, .header("Move to")]
        entries += library.folders.map { folder in
            .item(folder.name, checked: item.folder == folder.url) { library.move(item.url, to: folder.url) }
        }
        if item.folder != nil {
            entries.append(.item("Out of the Folder") { library.move(item.url, to: nil) })
        }
        return entries
    }

    private func commitRename(_ item: Library.Item) {
        renaming = nil
        library.rename(item, to: draft)
    }
}

private struct SidebarRow: View {
    let title: String
    var icon: Icon? = nil
    let trailing: String?
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    IconView(icon, size: 16)
                        .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                }
                Text(title)
                    .font(ThemeFont.label)
                    .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(ThemeFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, Theme.panelPad - 4)
            .frame(height: Theme.listRow)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                .fill(selected ? Theme.rowSelected : hovering ? Theme.rowHover : .clear))
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The saved thumbnail when there is one; otherwise the composition's shape
/// and ground, so an empty project still looks like its own frame.
private struct ProjectThumbnail: View {
    let item: Library.Item

    var body: some View {
        ZStack {
            Theme.canvas
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
            } else if let composition = item.composition {
                Group {
                    if composition.background.isTransparent {
                        Checkerboard(cell: 4)
                    } else {
                        Rectangle().fill(composition.background.color.opaque)
                    }
                }
                .aspectRatio(CGFloat(composition.width) / CGFloat(composition.height), contentMode: .fit)
                .padding(10)
            }
        }
    }
}
