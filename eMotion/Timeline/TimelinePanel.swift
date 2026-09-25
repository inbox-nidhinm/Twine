import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's surface: the transport, the ruler, and a row per action
/// under it, running the full width of the window.
struct TimelinePanel: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    static let rulerHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            TransportBar(controller: controller, editor: editor)
            PanelDivider()
            HStack(spacing: 0) {
                Color.clear.frame(width: TimelineRow.gutter)
                TimelineRuler(controller: controller, editor: editor)
            }
            .frame(height: Self.rulerHeight)
            PanelDivider()
            ActionTimeline(controller: controller, editor: editor)
        }
    }
}

/// Asks for the gap and staggers the selected actions: each starts that
/// much after the one in the row above it.
struct StaggerCard: View {
    let controller: EditorController
    let close: () -> Void

    @AppStorage("staggerGap") private var gap = 0.1

    var body: some View {
        PopupCard(title: "Stagger", width: Theme.cardWidth) {
            LabeledRow(label: "Gap") {
                UnitField(value: gap, decimals: 2, suffix: "s", accepts: { $0 >= 0 }) { gap = $0 }
            }
            .help("How long after the action in the row above each one starts.")
            PanelButton(title: "Stagger", icon: .stagger) {
                controller.staggerSelectedActions(gap: gap)
                close()
            }
        }
    }
}

// MARK: - Transport

private struct TransportBar: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    @Environment(MenuHost.self) private var menus
    @State private var staggerFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: Theme.barGap) {
            BarButton(icon: .jumpStart, help: "Go to the start (Home)") { controller.jumpToStart() }
            BarButton(icon: .stepBack, help: "Previous frame (comma; Shift for ten, Option for the previous action edge)") { controller.step(-1) }
            BarButton(icon: editor.isPlaying ? .pause : .play, help: editor.isPlaying ? "Pause (Space)" : "Play (Space)") {
                controller.togglePlay()
            }
            BarButton(icon: .stepForward, help: "Next frame (full stop; Shift for ten, Option for the next action edge)") { controller.step(1) }
            BarButton(icon: .jumpEnd, help: "Go to the end (End)") { controller.jumpToEnd() }
            BarButton(icon: .loop, help: editor.loops ? "Looping: playback starts over at the end" : "Stops at the end",
                      isOn: editor.loops) { editor.loops.toggle() }

            Button { editor.showsFrames.toggle() } label: {
                HStack(spacing: 4) {
                    Text(readout(editor.time))
                        .foregroundStyle(Theme.textPrimary)
                    Text("/ \(readout(controller.duration))")
                        .foregroundStyle(Theme.textTertiary)
                }
                .font(ThemeFont.label)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(height: Theme.control)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(editor.showsFrames ? "Show seconds" : "Show frames")
            .padding(.leading, 6)

            Spacer(minLength: 0)
            BarButton(icon: .stagger, help: "Stagger the selected actions", disabled: controller.selectedActions.count < 2) {
                menus.showPopup(at: CGPoint(x: staggerFrame.minX - Theme.cardWidth + staggerFrame.width, y: staggerFrame.maxY + 4)) {
                    StaggerCard(controller: controller) { menus.dismiss() }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { staggerFrame = $0 }
            BarButton(icon: .filter, help: editor.timelineOnlySelected ? "Show every layer's actions" : "Show only the selected layers' actions",
                      isOn: editor.timelineOnlySelected) { editor.timelineOnlySelected.toggle() }
            Text("\(controller.frameRate.label) fps")
                .font(ThemeFont.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, Theme.barPad + 2)
        .frame(height: Theme.barRow)
    }

    private func readout(_ t: Double) -> String {
        editor.showsFrames ? "\(controller.frameRate.frame(at: t))" : TimeFormat.clock(t)
    }
}
