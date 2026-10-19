import SwiftUI
import AppKit
import MotionModel
import Theme

/// Everything the app keeps outside a project, in the shelf's place. Each
/// kind of setting is a card under its name, laid out as the panels are,
/// its rows an icon, a name and the control, parted by dashed lines; the
/// cards sit in three columns when the window has room and two when not,
/// each going under the shortest column so far. At the foot is the
/// version, which is read rather than set. Every change is kept at once
/// (`AppSettings`); there is nothing to apply. Explanations are tooltips.
struct SettingsPage: View {
    @Bindable var library: Library
    let margin: CGFloat
    let titleBlock: CGFloat

    @Bindable private var settings = AppSettings.shared
    /// Read again after the projects folder is changed.
    @State private var projectsFolder = Creations.folder
    /// The Claude Code command was just copied.
    @State private var copiedCommand = false

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
                Masonry(minColumn: Theme.settingsCardMin, spacing: Theme.settingsCardGap) {
                    projects
                    newProjects
                    canvas
                    animation
                    timeline
                    sound
                    export
                    agents
                }
                .padding(margin)
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

    // MARK: Cards

    private var projects: some View {
        card("Projects") {
            folderRow(.folder, "Projects folder", projectsFolder,
                      help: "Where Twine keeps your projects. Projects already made stay where they are.") {
                Creations.chooseFolder(for: MainWindow.window) { chosen in
                    guard chosen else { return }
                    projectsFolder = Creations.folder
                    library.refresh()
                }
            }
        }
    }

    private var newProjects: some View {
        let c = settings.newProject
        return card("New projects") {
            row(.frame, "Size", help: "The size a new project starts at") {
                MenuField(value: Self.sizes.first { $0.width == c.width && $0.height == c.height }?.name ?? "Custom",
                          entries: {
                              Self.sizes.map { size in
                                  .item("\(size.name)  \(size.width) × \(size.height)",
                                        checked: size.width == c.width && size.height == c.height) {
                                      settings.newProject.width = size.width
                                      settings.newProject.height = size.height
                                  }
                              }
                          })
                .frame(width: Theme.settingsControl)
            }
            dashes
            row(.resize, "Width and height", help: "A new project's size in pixels") {
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
            dashes
            row(.keyframe, "Frame rate", help: "The frame rate a new project starts at") {
                MenuField(value: "\(c.frameRate.label) fps", entries: {
                    FrameRate.presets.map { rate in
                        .item("\(rate.label) fps", checked: rate == c.frameRate) { settings.newProject.frameRate = rate }
                    }
                })
                .frame(width: Theme.settingsControl)
            }
            dashes
            row(.stopwatch, "Length", help: "How long a new project runs, in seconds") {
                UnitField(value: c.duration, decimals: 2, suffix: "s", accepts: { $0 > 0 && $0 <= Composition.longest }) { v in
                    settings.newProject.duration = v
                }
                .frame(width: Theme.settingsControl)
            }
            dashes
            row(.fillSolid, "Background", help: "The colour behind a new project's layers") {
                HStack(spacing: Theme.rowGap * 2) {
                    ColorWell(color: c.background.color, size: Theme.control, title: "Background",
                              onChange: { settings.newProject.background.color = $0 })
                    HexField(color: c.background.color) { settings.newProject.background.color = $0 }
                }
                .frame(width: Theme.settingsControl)
            }
            dashes
            toggle(.opacity, "Transparent", isOn: c.background.isTransparent,
                   help: "A new project starts with no background, for exports that keep transparency") {
                settings.newProject.background.isTransparent.toggle()
            }
        }
    }

    private var canvas: some View {
        card("Canvas") {
            row(.arrowRight, "Nudge", help: "How far an arrow key moves the selection") {
                UnitField(value: settings.nudge, suffix: "px", accepts: Self.validNudge) { settings.nudge = $0 }
                    .frame(width: Theme.settingsControl)
            }
            dashes
            row(.move, "Shift nudge", help: "How far an arrow key moves the selection with Shift held") {
                UnitField(value: settings.shiftNudge, suffix: "px", accepts: Self.validNudge) { settings.shiftNudge = $0 }
                    .frame(width: Theme.settingsControl)
            }
        }
    }

    private var animation: some View {
        card("New actions") {
            row(tile: AnyView(EasingTile(preset: settings.actionEasing)), "Easing",
                help: "The easing a new action starts with. Presets keep their own.") {
                MenuField(value: settings.actionEasing.title, entries: {
                    EasingCard.order.map { preset in
                        .item(preset.title, checked: preset == settings.actionEasing) { settings.actionEasing = preset }
                    }
                })
                .frame(width: Theme.settingsControl)
            }
            dashes
            row(.stopwatch, "Length", help: "How long a new action runs, in seconds. Presets keep their own.") {
                UnitField(value: settings.actionDuration, decimals: 2, suffix: "s", accepts: { $0 > 0 && $0 <= 60 }) { v in
                    settings.actionDuration = v
                }
                .frame(width: Theme.settingsControl)
            }
        }
    }

    private var timeline: some View {
        card("Timeline") {
            toggle(.keyframe, "Show times as frames", isOn: settings.showsFrames,
                   help: "Times read as frame numbers rather than seconds, on the timeline and in the inspector") {
                settings.showsFrames.toggle()
            }
        }
    }

    private var sound: some View {
        card("Sound") {
            toggle(settings.playsSound ? .speaker : .speakerOff, "Play sound while editing", isOn: settings.playsSound,
                   help: "Whether playing in the editor and the export preview is heard. Exports always keep their sound.") {
                settings.playsSound.toggle()
            }
        }
    }

    private var export: some View {
        card("Export") {
            row(.export, "Save exports", help: "Ask where each export goes, or put every one in a folder") {
                MenuField(value: settings.exportFolder == nil ? "Ask Each Time" : "In a Folder", entries: {
                    [
                        .item("Ask Each Time", checked: settings.exportFolder == nil) { settings.exportFolder = nil },
                        .item("In a Folder…", checked: settings.exportFolder != nil) { chooseExportFolder() },
                    ]
                })
                .frame(width: Theme.settingsControl)
            }
            if let folder = settings.exportFolder {
                dashes
                folderRow(.folder, "Export folder", folder,
                          help: "Exports go here, numbered when a file of the same name is there already",
                          change: chooseExportFolder)
            }
            dashes
            toggle(.eye, "Show in Finder when done", isOn: settings.revealsExports,
                   help: "Each finished export is shown in the Finder") {
                settings.revealsExports.toggle()
            }
        }
    }

    private var agents: some View {
        card("AI apps") {
            toggle(.mcp, "Let AI apps use Twine", isOn: settings.allowsAgents,
                   help: "Claude, Cursor and other apps that speak MCP can read and change the open project, draw its frames and export it. Every change they make undoes like your own.") {
                settings.allowsAgents.toggle()
            }
            dashes
            row(.claude, "Claude Code", help: "Copies the command that adds Twine to Claude Code. Run it once in a terminal.") {
                PanelButton(title: copiedCommand ? "Copied" : "Copy Command") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(AgentBridge.claudeCommand, forType: .string)
                    copiedCommand = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCommand = false }
                }
                .frame(width: Theme.settingsButton)
            }
        }
    }

    // MARK: Pieces

    /// A kind of setting: its name over a card holding its rows.
    private func card<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.columnGap) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textSecondary)
                .padding(.leading, Theme.rowGap)
            // As far in at the top and bottom as at the sides: a row
            // already leaves `rowInset` round its tile, so the card adds
            // the rest.
            VStack(alignment: .leading, spacing: 0) { rows() }
                .padding(.horizontal, Theme.panelPad)
                .padding(.vertical, Theme.panelPad - Self.rowInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Flat on the page, with no shadow (the user's choice).
                .floatingPanel(shadow: false)
        }
    }

    /// The dashed line between two rows of a card.
    private var dashes: some View {
        Line()
            .stroke(Theme.border, style: StrokeStyle(lineWidth: Theme.hairline, dash: Theme.settingsDash))
            .frame(height: Theme.hairline)
    }

    /// An icon on its tile, a name, and the control at the right. The
    /// explanation is the row's tooltip.
    private func row<Control: View>(_ icon: Icon, _ label: String, help: String,
                                    @ViewBuilder _ control: () -> Control) -> some View {
        row(tile: AnyView(IconView(icon, size: Theme.settingsTileIcon)), label, help: help, control)
    }

    private func row<Control: View>(tile: AnyView, _ label: String, help: String,
                                    @ViewBuilder _ control: () -> Control) -> some View {
        HStack(spacing: Theme.panelPad) {
            Self.tile(tile)
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: Theme.columnGap)
            control()
        }
        .frame(height: Theme.settingsRow)
        .help(help)
    }

    private func toggle(_ icon: Icon, _ label: String, isOn: Bool, help: String,
                        _ action: @escaping () -> Void) -> some View {
        row(icon, label, help: help) { PillToggle(isOn: isOn, toggle: action) }
    }

    /// A folder's row: its name, then the path, with Change… and Show in
    /// Finder under it.
    private func folderRow(_ icon: Icon, _ label: String, _ folder: URL, help: String,
                           change: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Theme.columnGap) {
            row(icon, label, help: help) { EmptyView() }
            Text(Self.short(folder))
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: Theme.panelRow + 4, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                .help(folder.standardizedFileURL.path)
            HStack(spacing: Theme.columnGap) {
                PanelButton(title: "Change…", action: change)
                PanelButton(title: "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
            }
        }
        .padding(.bottom, Self.rowInset)
    }

    /// The room a row leaves above and below its tile.
    private static let rowInset = (Theme.settingsRow - Theme.settingsTile) / 2

    /// The rounded square an icon sits on at a row's left.
    private static func tile(_ content: AnyView) -> some View {
        content
            .foregroundStyle(Theme.textSecondary)
            .frame(width: Theme.settingsTile, height: Theme.settingsTile)
            .background(RoundedRectangle(cornerRadius: Theme.radiusWell).fill(Theme.panelRaised))
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
        NamedSize(name: "Landscape", width: 1920, height: 1080),
        NamedSize(name: "Portrait", width: 1080, height: 1920),
        NamedSize(name: "Square", width: 1080, height: 1080),
        NamedSize(name: "4K", width: 3840, height: 2160),
    ]

    private static func validDimension(_ v: Double) -> Bool { v >= 1 && v <= 16384 }
    private static func validNudge(_ v: Double) -> Bool { v > 0 && v <= 1000 }
}

/// The chosen easing's own curve, as the easing card's tiles draw it, for
/// the Easing row's icon.
private struct EasingTile: View {
    let preset: EasingPreset

    var body: some View {
        EasingPath(easing: .preset(preset, intensity: Easing.standardIntensity))
            .stroke(style: StrokeStyle(lineWidth: Theme.iconStroke * Theme.settingsTileIcon / 24, lineCap: .round))
            .frame(width: Theme.settingsTileIcon, height: Theme.settingsTileIcon)
    }
}

/// A level line across its frame, for dashing.
private nonisolated struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// Columns of cards, each laid under whichever column is shortest so far,
/// as many columns as fit at `minColumn` wide, two at least and three at
/// most, all as wide as the room shared between them.
struct Masonry: Layout {
    let minColumn: CGFloat
    let spacing: CGFloat
    var fewest = 2
    var most = 3

    /// SwiftUI also asks at no width and at endless width while sizing
    /// things up: those get the fewest and the most.
    private func columns(for width: CGFloat) -> Int {
        guard width.isFinite else { return most }
        let fit = (width + spacing) / (minColumn + spacing)
        return min(max(fit.isFinite ? Int(fit) : fewest, fewest), most)
    }

    /// Where each card goes, and how tall the whole is.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        let count = columns(for: width)
        let column = max((width - spacing * CGFloat(count - 1)) / CGFloat(count), 0)
        var heights = Array(repeating: CGFloat(0), count: count)
        var frames: [CGRect] = []
        for view in subviews {
            let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let h = view.sizeThatFits(ProposedViewSize(width: column, height: nil)).height
            let y = heights[shortest] == 0 ? 0 : heights[shortest] + spacing
            frames.append(CGRect(x: CGFloat(shortest) * (column + spacing), y: y, width: column, height: h))
            heights[shortest] = y + h
        }
        return (frames, heights.max() ?? 0)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let ideal = minColumn * CGFloat(fewest) + spacing
        let width = proposal.width.map { $0.isFinite ? $0 : minColumn * CGFloat(most) + spacing * CGFloat(most - 1) } ?? ideal
        return CGSize(width: width, height: arrange(subviews, width: width).height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(subviews, width: bounds.width).frames
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }
}
