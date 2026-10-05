import SwiftUI
import AppKit
import MotionModel
import Theme

/// What the app opens onto: every project in `Twine Creations`, as a shelf,
/// with its folders down the sidebar, laid out as re-Flip's home screen is.
/// Cards drag onto a folder, or onto All Projects to come out of one.
struct HomeView: View {
    @Bindable var library: Library

    @Environment(MenuHost.self) private var menus
    @State private var hovered: URL?
    /// The sidebar row under the pointer, by its title (folder names are
    /// unique on disk, and none can be called All Projects).
    @State private var hoveredRow: String?
    @State private var renaming: URL?
    @State private var draft = ""
    @FocusState private var renameFocused: Bool
    /// The New Folder row, turned into a field for the new folder's name.
    @State private var addingFolder = false
    /// The folder being renamed in the sidebar.
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
    /// re-Flip's card: 158 wide, a square thumbnail inset 5, the name and
    /// date inset 12 under it, and 12 of foot.
    private let card: CGFloat = 158
    private let cardPad: CGFloat = 5
    private let cardFoot: CGFloat = 12
    private let captionInset: CGFloat = 12
    private let thumbRadius: CGFloat = 6
    private let gutter: CGFloat = 24
    private let margin: CGFloat = 18

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            if library.showsSettings {
                SettingsPage(library: library, margin: margin, titleBlock: titleBlock)
            } else {
                shelf
            }
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
        .overlay {
            if let item = library.info {
                ProjectInfoCard(item: item, library: library) { library.info = nil }
                    .transition(.opacity)
            }
        }
        .overlay {
            if let search = library.search {
                SearchCard(source: search) { [library] in
                    library.search = nil
                    MainWindow.window.makeFirstResponder(nil)
                }
                .transition(.opacity)
            }
        }
        .overlay { MenuLayer() }
        // Over everything: on a first launch it is the whole of what shows.
        .overlay {
            if OnboardingState.shared.isShowing {
                OnboardingView {
                    library.selectedFolder = nil
                    library.refresh()
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.14), value: library.showVersionHistory)
        .animation(.easeOut(duration: 0.14), value: library.info?.url)
        .animation(.easeOut(duration: 0.12), value: library.search != nil)
        .animation(.easeOut(duration: 0.2), value: OnboardingState.shared.isShowing)
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
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Theme.border)
                .frame(height: Theme.hairline)
                .padding(.horizontal, Theme.panelPad)
                .padding(.bottom, Theme.rowGap)

            // The folders scroll when there are more than fit (5 October
            // 2026): before, every one made the sidebar taller and the window
            // grew to hold it. Settings stays at the foot, outside.
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sidebarRow("All Projects", on: !library.showsSettings && library.selectedFolder == nil) { library.selectedFolder = nil }
                        .background(dropHighlight(Creations.folder.standardizedFileURL))
                        .dropDestination(for: URL.self) { urls, _ in drop(urls, into: nil) } isTargeted: {
                            target(Creations.folder.standardizedFileURL, $0)
                        }
                    ForEach(library.folders) { folder in folderRow(folder) }

                    // Under the folders: a dim row that turns into the new one's name.
                    if addingFolder {
                        nameField(placeholder: "Folder name", onSubmit: endNewFolder, onCancel: {
                            folderDraft = ""
                            addingFolder = false
                        })
                    } else {
                        sidebarRow("New Folder", dim: true) {
                            folderDraft = ""
                            renamingFolder = nil
                            addingFolder = true
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            // Parts the list from Settings, as the title is parted from it.
            Rectangle().fill(Theme.border)
                .frame(height: Theme.hairline)
                .padding(.horizontal, Theme.panelPad)
                .padding(.top, Theme.rowGap)
                .padding(.bottom, Theme.rowGap)

            // Opens Settings; picking a folder is what comes back.
            sidebarRow("Settings", icon: .settings, on: library.showsSettings) {
                endNewFolder()
                library.showsSettings = true
            }
            .padding(.bottom, Theme.rowGap)
        }
        .frame(width: sidebar)
        .frame(maxHeight: .infinity)
        .floatingPanel()
        .padding(Theme.floatInset)
    }

    /// One line in the sidebar, at the layer row's measurements: 32 tall, the
    /// fill inset 4 with a 4 pt corner, the words 12 in.
    private func sidebarRow(_ title: String, icon: Icon? = nil, dim: Bool = false,
                            on: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon { IconView(icon, size: 16) }
                Text(title)
                    .font(ThemeFont.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(on ? Theme.textPrimary : dim ? Theme.textTertiary : Theme.textSecondary)
            // As far in on the right as on the left.
            .padding(.horizontal, Theme.panelPad)
            .frame(height: Theme.listRow)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                .fill(on ? Theme.rowSelected : hoveredRow == title ? Theme.rowHover : .clear)
                .padding(.horizontal, Theme.rowGap))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredRow = title } else if hoveredRow == title { hoveredRow = nil }
        }
    }

    /// A field in a row's place, the same size, for naming a folder.
    private func nameField(placeholder: String, onSubmit: @escaping () -> Void, onCancel: @escaping () -> Void) -> some View {
        TextField(placeholder, text: $folderDraft)
            .textFieldStyle(.plain)
            .font(ThemeFont.label)
            .foregroundStyle(Theme.textPrimary)
            .focused($folderFocused)
            // As far in on the right as on the left.
            .padding(.horizontal, Theme.panelPad)
            .frame(height: Theme.listRow)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                .fill(Theme.panelRaised)
                .padding(.horizontal, Theme.rowGap))
            .onAppear { DispatchQueue.main.async { folderFocused = true } }
            .onSubmit(onSubmit)
            // Clicking away keeps what was typed.
            .onChange(of: folderFocused) { _, now in if !now { onSubmit() } }
            .onExitCommand(perform: onCancel)
    }

    /// Makes the folder if a name was typed; an empty field costs nothing.
    private func endNewFolder() {
        guard addingFolder else { return }
        addingFolder = false
        let name = folderDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        folderDraft = ""
        guard !name.isEmpty, let url = library.newFolder(named: name) else { return }
        library.selectedFolder = url
    }

    // MARK: Folders

    @ViewBuilder private func folderRow(_ folder: Library.Folder) -> some View {
        if renamingFolder == folder.url {
            nameField(placeholder: "Folder name", onSubmit: { commitFolderRename(folder) },
                      onCancel: { renamingFolder = nil })
        } else {
            sidebarRow(folder.name, on: !library.showsSettings && library.selectedFolder == folder.url) {
                library.selectedFolder = folder.url
            }
            .background(dropHighlight(folder.url))
            .dropDestination(for: URL.self) { urls, _ in drop(urls, into: folder.url) } isTargeted: {
                target(folder.url, $0)
            }
            .rightClickMenu {
                let n = library.count(in: folder)
                return [
                    .item("Rename") {
                        addingFolder = false
                        folderDraft = folder.name
                        renamingFolder = folder.url
                    },
                    .item("Show in Finder") { library.reveal(folder) },
                    .separator,
                    // The count says what goes with it, before the click.
                    .item(n > 0 ? "Move Folder to Trash  (\(n) project\(n == 1 ? "" : "s"))" : "Move Folder to Trash") {
                        library.moveToTrash(folder)
                    },
                ]
            }
        }
    }

    private func commitFolderRename(_ folder: Library.Folder) {
        guard renamingFolder == folder.url else { return }
        renamingFolder = nil
        library.rename(folder, to: folderDraft)
    }

    /// A row lights up while a card is held over it.
    private func dropHighlight(_ url: URL) -> some View {
        RoundedRectangle(cornerRadius: Theme.radiusRow)
            .strokeBorder(Theme.accent, lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow).fill(Theme.rowCurrent))
            .padding(.horizontal, Theme.rowGap)
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
                    .displayTitle(21)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                PanelButton(title: "New Project", icon: .plus) { library.newProject() }
                    .fixedSize()
                    .help("New Project (⌘N)")
            }
            .padding(.leading, margin)
            // Wider than the title's own inset: a filled control that close to
            // the edge reads as though it is about to fall off it.
            .padding(.trailing, margin + 10)
            .padding(.bottom, 12)
            .frame(height: titleBlock, alignment: .bottom)
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())

            Rectangle().fill(Theme.border).frame(height: Theme.hairline)

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
        let lit = hovered == item.url || renaming == item.url
        return VStack(alignment: .leading, spacing: 0) {
            // No ground of its own: the picture keeps its shape, as wide as
            // the card and as tall as that makes it, up to a square for a
            // tall one, with nothing filling around it.
            ProjectThumbnail(item: item, side: card - cardPad * 2, radius: thumbRadius)
                .frame(width: card - cardPad * 2)

            Group {
                if renaming == item.url {
                    TextField("", text: $draft)
                        .textFieldStyle(.plain)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .focused($renameFocused)
                        .padding(.horizontal, 6)
                        .frame(height: Theme.panelRow - 2)
                        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                        .padding(.top, 8)
                        .onAppear { DispatchQueue.main.async { renameFocused = true } }
                        .onSubmit { commitRename(item) }
                        .onExitCommand { renaming = nil }
                        .onChange(of: renameFocused) { _, now in if !now, renaming == item.url { commitRename(item) } }
                } else {
                    Text(item.name)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .padding(.top, 10)
                    // The date only; in All Projects, after the folder it is in.
                    Text([library.selectedFolder == nil ? item.folder?.lastPathComponent : nil,
                          item.modified.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                        .font(ThemeFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, captionInset)
        }
        .padding(.horizontal, cardPad)
        .padding(.top, cardPad)
        .padding(.bottom, cardFoot)
        .frame(width: card, alignment: .leading)
        // The sidebar's own colour under the pointer, and nothing otherwise.
        .background(RoundedRectangle(cornerRadius: Theme.radiusPanel).fill(lit ? Theme.panel : .clear))
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
                .item("Info") { library.info = item },
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

/// The saved thumbnail when there is one; otherwise the composition's shape
/// and ground, so an empty project still looks like its own frame. Fitted
/// inside the card's square with its own rounded corners and nothing behind.
private struct ProjectThumbnail: View {
    let item: Library.Item
    /// The widest and tallest it may be.
    let side: CGFloat
    let radius: CGFloat

    /// Width over height: the picture's, or the composition's.
    private var aspect: CGFloat {
        if let size = item.thumbnail?.size, size.width > 0, size.height > 0 { return size.width / size.height }
        if let c = item.composition, c.width > 0, c.height > 0 { return CGFloat(c.width) / CGFloat(c.height) }
        return 16 / 9
    }

    /// Sized from its proportions rather than by fitting into a square, which
    /// would hold the whole square open around a wide picture.
    private var size: CGSize {
        aspect >= 1 ? CGSize(width: side, height: side / aspect) : CGSize(width: side * aspect, height: side)
    }

    var body: some View {
        Group {
            if let thumbnail = item.thumbnail {
                Image(nsImage: thumbnail).resizable()
            } else if let composition = item.composition, composition.background.isTransparent {
                Checkerboard(cell: 4)
            } else if let composition = item.composition {
                Rectangle().fill(composition.background.color.opaque)
            } else {
                Rectangle().fill(Theme.panelRaised)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}
