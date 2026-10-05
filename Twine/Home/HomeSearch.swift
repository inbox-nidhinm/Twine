import AppKit
import SwiftUI
import Theme

/// What the ⌘K card offers on the home screen: every project by name (the
/// latest few with nothing typed), with what its right-click menu does a
/// Tab away; the folders; New Folder and Settings; and the menu commands
/// that can run here.
extension Library {
    func searchSource() -> SearchSource {
        let latest = 6
        let projects = items.enumerated().map { i, item in projectItem(item, onlyWhenSearching: i >= latest) }
        let folders = [SearchItem(id: "folder.all", title: "All Projects", kind: "Folder", icon: .folder,
                                  isOn: !showsSettings && selectedFolder == nil, run: { [weak self] in self?.selectedFolder = nil })]
            + self.folders.map { folder in
                SearchItem(id: "folder.\(folder.url.path)", title: folder.name, kind: "Folder", icon: .folder,
                           isOn: !showsSettings && selectedFolder == folder.url, run: { [weak self] in self?.selectedFolder = folder.url })
            }
        let commands = [
            SearchItem(id: "home.newFolder", title: "New Folder", kind: "Home", icon: .folder, keywords: ["make", "create"],
                       naming: ("New Folder", "", { [weak self] name in
                if let url = self?.newFolder(named: name) { self?.selectedFolder = url }
            })),
            SearchItem(id: "home.settings", title: "Settings", kind: "Home", icon: .settings,
                       keywords: ["preferences", "options"], run: { [weak self] in self?.showsSettings = true }),
        ]
        return SearchSource(sections: [SearchSection(title: "Projects", items: projects),
                                       SearchSection(title: "Folders", items: folders),
                                       SearchSection(title: "Home", items: commands)]
                                + MainMenu.searchSections(except: [#selector(AppDelegate.showHome(_:))]),
                            recentsKey: "searchRecents.home")
    }

    /// A project: Return opens it; Tab shows its right-click menu's items.
    private func projectItem(_ item: Item, onlyWhenSearching: Bool) -> SearchItem {
        SearchItem(id: "project.\(item.url.path)", title: item.name, kind: "Project",
                   detail: item.folder?.lastPathComponent, thumbnail: item.thumbnail,
                   swatch: item.composition.map { $0.background.isTransparent ? Theme.panelRaised : $0.background.color.opaque }
                       ?? Theme.panelRaised,
                   onlyWhenSearching: onlyWhenSearching, run: { [weak self] in self?.open(item) },
                   more: { [weak self] in self?.projectCommands(item) ?? [] })
    }

    /// The project card's right-click menu, as the card lists it.
    private func projectCommands(_ item: Item) -> [SearchItem] {
        let key = "project.\(item.url.path)"
        var commands = [
            SearchItem(id: "\(key).open", title: "Open", kind: "Project", run: { [weak self] in self?.open(item) }),
            SearchItem(id: "\(key).rename", title: "Rename", kind: "Project",
                       naming: ("Rename", item.name, { [weak self] name in self?.rename(item, to: name) })),
            SearchItem(id: "\(key).duplicate", title: "Duplicate", kind: "Project", run: { [weak self] in self?.duplicate(item) }),
            SearchItem(id: "\(key).finder", title: "Show in Finder", kind: "Project", run: { [weak self] in self?.reveal(item) }),
            SearchItem(id: "\(key).info", title: "Info", kind: "Project", run: { [weak self] in self?.info = item }),
        ]
        commands += folders.filter { $0.url != item.folder }.map { folder in
            SearchItem(id: "\(key).move.\(folder.url.path)", title: "Move to \(folder.name)", kind: "Project", icon: .folder,
                       run: { [weak self] in self?.move(item.url, to: folder.url) })
        }
        if item.folder != nil {
            commands.append(SearchItem(id: "\(key).out", title: "Move Out of the Folder", kind: "Project", icon: .folder,
                                       run: { [weak self] in self?.move(item.url, to: nil) }))
        }
        commands.append(SearchItem(id: "\(key).trash", title: "Move to Trash", kind: "Project", icon: .trash,
                                   run: { [weak self] in self?.moveToTrash(item) }))
        return commands
    }
}
