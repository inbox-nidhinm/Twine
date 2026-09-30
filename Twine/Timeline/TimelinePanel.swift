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
                Rectangle().fill(Theme.border).frame(width: Theme.hairline)
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

/// A scene's name, typed; Return keeps it.
struct SceneNameCard: View {
    let controller: EditorController
    let scene: TimelineScene
    let close: () -> Void

    @State private var name = ""
    @FocusState private var typing: Bool

    var body: some View {
        PopupCard(title: "Rename Scene", width: Theme.cardWidth) {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .focused($typing)
                .padding(.horizontal, 8)
                .frame(height: Theme.control)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                .focusRing(typing)
                .onSubmit {
                    controller.renameScene(scene.id, to: name)
                    close()
                }
                .onAppear {
                    name = scene.name
                    typing = true
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
        HStack(spacing: Theme.transportGap) {
            button(.jumpStart, "Go to the start (Home)") { controller.jumpToStart() }
            button(.stepBack, "Previous frame (comma; Shift for ten, Option for the previous action edge)") { controller.step(-1) }
            // White while playing, so the pause reads as what is going on.
            button(editor.isPlaying ? .pause : .play, editor.isPlaying ? "Pause (Space)" : "Play (Space)",
                   lit: editor.isPlaying) { controller.togglePlay() }
            button(.stepForward, "Next frame (full stop; Shift for ten, Option for the next action edge)") { controller.step(1) }
            button(.jumpEnd, "Go to the end (End)") { controller.jumpToEnd() }
            BarButton(icon: .loop, help: editor.loops ? "Looping: playback starts over at the end" : "Stops at the end",
                      isOn: editor.loops, size: Theme.transportButton, iconBox: Theme.transportIcon, hoverFill: .clear,
                      onFill: Theme.chosen, hoverLights: true) { editor.loops.toggle() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Small, and lit white under the pointer rather than filled.
    private func button(_ icon: Icon, _ help: String, lit: Bool = false, _ action: @escaping () -> Void) -> some View {
        BarButton(icon: icon, help: help, size: Theme.transportButton, iconBox: Theme.transportIcon, hoverFill: .clear,
                  lit: lit, hoverLights: true, action: action)
    }
}
