import SwiftUI
import Theme

/// What the app has been, newest first.
///
/// Every change to the app gets an entry here, kept current as part of the
/// work rather than caught up with later. Put a new build at the top of
/// `builds`; the numbers count themselves off the list. `make-app.sh` reads the
/// same count into the bundle's version, so nothing else needs editing.
enum VersionHistory {
    static var version: String { "\(builds.count)" }

    struct Build: Identifiable {
        let date: String
        let title: String
        let changes: [String]
        var id: String { date + title }
    }

    static func number(of build: Build) -> Int {
        guard let i = builds.firstIndex(where: { $0.id == build.id }) else { return 0 }
        return builds.count - i
    }

    static let builds: [Build] = [
        .init(date: "25 September 2026", title: "Everything worked out at any moment", changes: [
            "Every property can now be worked out at any moment of the animation, between frames included: keyframes, the easing presets, custom curves, holds and springs.",
            "Colours blend through a perceptual colour space, so red to blue passes through purple rather than grey.",
            "A spring keeps its own natural length; stretch the segment and the bounce stretches with it rather than jumping.",
            "The renderer that draws the canvas also draws off screen, which is how the export will draw, so what you see is what you get.",
            "Home screen cards show each project's first frame.",
        ]),
        .init(date: "25 September 2026", title: "Clicks land where they should", changes: [
            "The Design and Animate switch, the Composition header and the tools answer clicks again. The inspector's list had been stretching up under the title bar and catching clicks meant for the controls above it, and even sent some to the width field.",
            "Nothing takes the keyboard when a window opens, so typing no longer goes into the composition's width.",
            "Clicking anywhere outside a text field ends the edit and keeps what was typed.",
            "The traffic lights stay in the left panel's corner without the loop that crashed the app when a project opened in the background.",
            "Section headers are real buttons, so a click anywhere on the row folds them.",
        ]),
        .init(date: "25 September 2026", title: "The foundation", changes: [
            "A home screen of every project in eMotion Creations, newest first, with open, rename, duplicate, show in Finder and move to Trash.",
            "New projects are written to disk the moment they are made and save themselves from then on. Closing a window never asks a question, and File > Revert To browses older versions.",
            "The project file is a package: document.json with a format version, and a media folder for imported files.",
            "Every change goes through one set of commands, so every change can be undone. A drag or a colour pick undoes as one step.",
            "The editor's shell: the canvas full-bleed, the layers panel and the inspector floating over it, and the Design and Animate switch at the head of the inspector.",
            "Composition settings: size, frame rate (including 23.976, 29.97, 59.94 and custom rates), duration, and a background colour or transparency.",
            "Flip's design system, with a light blue accent, from the Figma file: its colours, type, metrics, grain and controls.",
        ]),
    ]
}

/// The list, on the same floating card as everything else.
struct VersionHistoryCard: View {
    let dismiss: () -> Void

    private let cardWidth: CGFloat = 600
    private let pad: CGFloat = 18

    var body: some View {
        ZStack {
            Theme.badge
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Version History")
                        .font(ThemeFont.labelStrong)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer(minLength: 0)
                    IconButton(icon: .close, help: "Close (Esc)", action: dismiss)
                }
                .padding(.horizontal, pad)
                .frame(height: 38)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(VersionHistory.builds) { build in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(build.title)
                                        .displayTitle(20)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer(minLength: 0)
                                    Text("Build \(VersionHistory.number(of: build)) · \(build.date)")
                                        .font(ThemeFont.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                }
                                ForEach(build.changes, id: \.self) { change in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Circle().fill(Theme.textTertiary).frame(width: 3, height: 3)
                                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 3 }
                                        Text(change)
                                            .font(ThemeFont.label)
                                            .foregroundStyle(Theme.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                    .padding(pad)
                }
                .frame(maxHeight: 520)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: cardWidth)
            .floatingPanel()
            .onExitCommand(perform: dismiss)
        }
    }
}
