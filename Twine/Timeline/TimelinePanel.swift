import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's surface, running the full width of the window: the play
/// controls over a column of labels, the ruler beside them, and a row per
/// action underneath, in the order the actions were added.
struct TimelinePanel: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    static let headerHeight: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TransportBar(controller: controller, editor: editor)
                    .frame(width: TimelineRow.labelWidth - 1)
                Rectangle().fill(Theme.border).frame(width: 1)
                TimelineRuler(controller: controller, editor: editor)
            }
            .frame(height: Self.headerHeight)
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

/// The play controls, centred over the labels. The time itself rides in the
/// playhead's pill in the ruler.
private struct TransportBar: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    var body: some View {
        HStack(spacing: 2) {
            BarButton(icon: .jumpStart, help: "Go to the start (Home)") { controller.jumpToStart() }
            BarButton(icon: .stepBack, help: "Previous frame (comma; Shift for ten, Option for the previous action edge)") { controller.step(-1) }
            BarButton(icon: editor.isPlaying ? .pause : .play, help: editor.isPlaying ? "Pause (Space)" : "Play (Space)") {
                controller.togglePlay()
            }
            BarButton(icon: .stepForward, help: "Next frame (full stop; Shift for ten, Option for the next action edge)") { controller.step(1) }
            BarButton(icon: .jumpEnd, help: "Go to the end (End)") { controller.jumpToEnd() }
            BarButton(icon: .loop, help: editor.loops ? "Looping: playback starts over at the end" : "Stops at the end",
                      isOn: editor.loops) { editor.loops.toggle() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
