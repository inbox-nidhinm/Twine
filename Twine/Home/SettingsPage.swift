import SwiftUI
import AppKit
import MotionModel
import Theme

/// Everything the app keeps outside a project, in the shelf's place, as
/// re-Flip's Settings page is: a column of rows, each a name and its
/// control, and at the foot the version, which is read rather than set.
/// Every change is kept at once (`AppSettings`); there is nothing to apply.
struct SettingsPage: View {
    @Bindable var library: Library
    let margin: CGFloat
    let titleBlock: CGFloat

    @Bindable private var settings = AppSettings.shared
    /// Read again after the projects folder is changed.
    @State private var projectsFolder = Creations.folder

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .displayTitle(21)
                .foregroundStyle(Theme.textPrimary)
                .padding(.leading, margin)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: titleBlock, alignment: .bottom)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            Rectangle().fill(Theme.border).frame(height: Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.readingSectionGap) {
                    projects
                    newProjects
                    canvas
                    animation
                    timeline
                    sound
                    export
                }
                .frame(width: Theme.settingsColumn, alignment: .leading)
                .padding(margin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Not a setting: nothing here changes what the app does, so it
            // sits apart, at the foot.
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
            HStack(spacing: Theme.columnGap) {
                PanelButton(title: "Version History") { library.showVersionHistory = true }
                    .frame(width: Theme.settingsButton)
                Text("Build \(VersionHistory.version) · \(VersionHistory.release)")
                    .font(ThemeFont.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(margin)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Sections

    private var projects: some View {
        section("Projects") {
            folderBox(projectsFolder, change: {
                Creations.chooseFolder(for: MainWindow.window) { chosen in
                    guard chosen else { return }
                    projectsFolder = Creations.folder
                    library.refresh()
                }
            })
            .help("Where Twine keeps your projects. Projects already made stay where they are.")
        }
    }

    private var newProjects: some View {
        let c = settings.newProject
        return section("New projects") {
            row("Size", help: "The size a new project starts at") {
                MenuField(value: Self.sizes.first { $0.width == c.width && $0.height == c.height }?.name ?? "Custom",
                          entries: {
                              Self.sizes.map { size in
                                  .item(size.name, checked: size.width == c.width && size.height == c.height) {
                                      settings.newProject.width = size.width
                                      settings.newProject.height = size.height
                                  }
                              }
                          })
                .frame(width: Theme.settingsControl)
            }
            row("Width and height", help: "In pixels") {
                HStack(spacing: Theme.rowGap * 2) {
                    UnitField(unit: "W", value: Double(c.width), accepts: Self.validDimension) { v in
                        settings.newProject.width = Int(v.rounded())
                    }
                    UnitField(unit: "H", value: Double(c.height), accepts: Self.validDimension) { v in
                        settings.newProject.height = Int(v.rounded())
                    }
                }
                .frame(width: Theme.settingsControl)
            }
            row("Frame rate", help: "The frame rate a new project starts at") {
                MenuField(value: "\(c.frameRate.label) fps", entries: {
                    FrameRate.presets.map { rate in
                        .item("\(rate.label) fps", checked: rate == c.frameRate) { settings.newProject.frameRate = rate }
                    }
                })
                .frame(width: Theme.settingsControl)
            }
            row("Length", help: "How long a new project runs, in seconds") {
                UnitField(value: c.duration, decimals: 2, suffix: "s", accepts: { $0 > 0 && $0 <= Composition.longest }) { v in
                    settings.newProject.duration = v
                }
                .frame(width: Theme.settingsControl)
            }
            row("Background", help: "The colour behind a new project's layers") {
                HStack(spacing: Theme.rowGap * 2) {
                    ColorWell(color: c.background.color, size: Theme.control, title: "Background",
                              onChange: { settings.newProject.background.color = $0 })
                    HexField(color: c.background.color) { settings.newProject.background.color = $0 }
                }
                .frame(width: Theme.settingsControl)
            }
            toggle("Transparent background", isOn: c.background.isTransparent,
                   help: "A new project starts with no background, for exports that keep transparency") {
                settings.newProject.background.isTransparent.toggle()
            }
        }
    }

    private var canvas: some View {
        section("Canvas") {
            row("Nudge", help: "How far an arrow key moves the selection") {
                UnitField(value: settings.nudge, suffix: "px", accepts: Self.validNudge) { settings.nudge = $0 }
                    .frame(width: Theme.settingsControl)
            }
            row("Shift nudge", help: "How far an arrow key moves the selection with Shift held") {
                UnitField(value: settings.shiftNudge, suffix: "px", accepts: Self.validNudge) { settings.shiftNudge = $0 }
                    .frame(width: Theme.settingsControl)
            }
        }
    }

    private var animation: some View {
        section("New actions") {
            row("Easing", help: "The easing a new action starts with. Presets keep their own.") {
                MenuField(value: settings.actionEasing.title, entries: {
                    EasingCard.order.map { preset in
                        .item(preset.title, checked: preset == settings.actionEasing) { settings.actionEasing = preset }
                    }
                })
                .frame(width: Theme.settingsControl)
            }
            row("Length", help: "How long a new action runs, in seconds. Presets keep their own.") {
                UnitField(value: settings.actionDuration, decimals: 2, suffix: "s", accepts: { $0 > 0 && $0 <= 60 }) { v in
                    settings.actionDuration = v
                }
                .frame(width: Theme.settingsControl)
            }
        }
    }

    private var timeline: some View {
        section("Timeline") {
            toggle("Show times as frames", isOn: settings.showsFrames,
                   help: "Times read as frame numbers rather than seconds, on the timeline and in the inspector") {
                settings.showsFrames.toggle()
            }
        }
    }

    private var sound: some View {
        section("Sound") {
            toggle("Play sound while editing", isOn: settings.playsSound,
                   help: "Whether playing in the editor and the export preview is heard. Exports always keep their sound.") {
                settings.playsSound.toggle()
            }
        }
    }

    private var export: some View {
        section("Export") {
            row("Save exports", help: "Ask where each export goes, or put every one in a folder") {
                MenuField(value: settings.exportFolder == nil ? "Ask Each Time" : "In a Folder", entries: {
                    [
                        .item("Ask Each Time", checked: settings.exportFolder == nil) { settings.exportFolder = nil },
                        .item("In a Folder…", checked: settings.exportFolder != nil) { chooseExportFolder() },
                    ]
                })
                .frame(width: Theme.settingsControl)
            }
            if let folder = settings.exportFolder {
                folderBox(folder, change: chooseExportFolder)
                    .help("Exports go here, numbered when a file of the same name is there already")
            }
            toggle("Show in Finder when done", isOn: settings.revealsExports,
                   help: "Each finished export is shown in the Finder") {
                settings.revealsExports.toggle()
            }
        }
    }

    // MARK: Pieces

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowGap) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textPrimary)
            content()
        }
    }

    /// A name and its control. The explanation is the row's tooltip.
    private func row<Control: View>(_ label: String, help: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: Theme.columnGap) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: Theme.settingsLabel, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
        .frame(height: Theme.panelRow + 4)
        .help(help)
    }

    private func toggle(_ label: String, isOn: Bool, help: String, _ action: @escaping () -> Void) -> some View {
        row(label, help: help) {
            HStack {
                Spacer(minLength: 0)
                PillToggle(isOn: isOn, toggle: action)
            }
            .frame(width: Theme.settingsControl)
        }
    }

    /// A folder's path, then Change… and Show in Finder under it.
    private func folderBox(_ folder: URL, change: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.rowGap * 2) {
            Text(Self.short(folder))
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Theme.panelRow + 4, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
            HStack(spacing: Theme.rowGap * 2) {
                PanelButton(title: "Change…", action: change)
                    .frame(width: Theme.settingsButton)
                PanelButton(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                    .frame(width: Theme.settingsButton)
            }
        }
    }

    private func chooseExportFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Where should exports go?"
        if let folder = settings.exportFolder { panel.directoryURL = folder }
        panel.beginSheetModal(for: MainWindow.window) { response in
            guard response == .OK, let url = panel.url else { return }
            settings.exportFolder = url
        }
    }

    /// The home folder as ~, as the Finder's path bar reads.
    private static func short(_ url: URL) -> String {
        let path = url.standardizedFileURL.path, home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    private struct NamedSize {
        let name: String
        let width: Int
        let height: Int
    }

    private static let sizes = [
        NamedSize(name: "Landscape  1920 × 1080", width: 1920, height: 1080),
        NamedSize(name: "Portrait  1080 × 1920", width: 1080, height: 1920),
        NamedSize(name: "Square  1080 × 1080", width: 1080, height: 1080),
        NamedSize(name: "4K  3840 × 2160", width: 3840, height: 2160),
    ]

    private static func validDimension(_ v: Double) -> Bool { v >= 1 && v <= 16384 }
    private static func validNudge(_ v: Double) -> Bool { v > 0 && v <= 1000 }
}
