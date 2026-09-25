import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's surface: the transport, the ruler, and the tracks under
/// it. The tracks are empty until actions get their rows (redesign
/// milestone 4).
struct TimelinePanel: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    /// The names column's width.
    static let namesWidth: CGFloat = 196
    static let rulerHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            TransportBar(controller: controller, editor: editor)
            PanelDivider()
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.namesWidth)
                TimelineRuler(controller: controller, editor: editor)
            }
            .frame(height: Self.rulerHeight)
            PanelDivider()
            HStack(spacing: 0) {
                Color.clear
                    .frame(width: Self.namesWidth)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
                TimelineTracks(controller: controller, editor: editor)
            }
        }
    }
}

// MARK: - Transport

private struct TransportBar: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: Theme.barGap) {
            BarButton(icon: .jumpStart, help: "Go to the start (Home)") { controller.jumpToStart() }
            BarButton(icon: .stepBack, help: "Previous frame ([)") { controller.step(-1) }
            BarButton(icon: editor.isPlaying ? .pause : .play, help: editor.isPlaying ? "Pause (Space)" : "Play (Space)") {
                controller.togglePlay()
            }
            BarButton(icon: .stepForward, help: "Next frame (])") { controller.step(1) }
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
