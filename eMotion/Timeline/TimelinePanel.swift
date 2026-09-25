import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Animate mode's surface: the transport, then the layers down the left and
/// their bars and keyframes along time on the right, with the ruler above.
struct TimelinePanel: View {
    let controller: EditorController
    @Bindable var editor: EditorModel

    /// The names column's width.
    static let namesWidth: CGFloat = 196
    static let rulerHeight: CGFloat = 24

    var body: some View {
        let rows = TimelineRow.rows(of: controller.project, expanded: editor.timelineExpanded)
        VStack(spacing: 0) {
            TransportBar(controller: controller, editor: editor)
            PanelDivider()
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.namesWidth)
                TimelineRuler(controller: controller, editor: editor)
            }
            .frame(height: Self.rulerHeight)
            PanelDivider()
            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        ForEach(rows) { row in
                            TimelineNameRow(row: row, controller: controller, editor: editor)
                        }
                    }
                    .frame(width: Self.namesWidth, alignment: .top)
                    .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 1) }
                    TimelineTracks(controller: controller, editor: editor, rows: rows)
                        .frame(height: max(CGFloat(rows.count) * TimelineRow.height, 1))
                }
            }
            .scrollIndicators(.never)
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

// MARK: - Names

private struct TimelineNameRow: View {
    let row: TimelineRow
    let controller: EditorController
    @Bindable var editor: EditorModel

    @State private var hovering = false

    var body: some View {
        Group {
            switch row.kind {
            case .layer(let layer, let depth): layerRow(layer, depth: depth)
            case .property(let layer, let property, let depth): propertyRow(layer, property, depth: depth)
            }
        }
        .frame(height: TimelineRow.height)
        .onHover { hovering = $0 }
    }

    private func layerRow(_ layer: Layer, depth: Int) -> some View {
        let selected = editor.selection.contains(layer.id)
        let open = editor.timelineExpanded.contains(layer.id)
        return HStack(spacing: 4) {
            Color.clear.frame(width: CGFloat(depth) * 12, height: 1)
            if TimelineRow.canExpand(layer) {
                Button {
                    if open { editor.timelineExpanded.remove(layer.id) } else { editor.timelineExpanded.insert(layer.id) }
                } label: {
                    IconView(.chevronRight, size: 12)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 14, height: TimelineRow.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 14, height: 1)
            }
            IconView(layer.icon, size: 14)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textTertiary)
            Text(layer.name)
                .font(ThemeFont.label)
                .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .background(Rectangle().fill(selected ? Theme.rowSelected : hovering ? Theme.rowHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture {
            editor.focus = .timeline
            controller.select([layer.id], extending: NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command))
        }
        .opacity(layer.isVisible ? 1 : 0.5)
    }

    private func propertyRow(_ layer: Layer, _ property: PropertyID, depth: Int) -> some View {
        let marks = LayerProperties.get(property, of: layer)?.marks ?? []
        let tolerance = controller.frameRate.frameDuration / 2
        let here = marks.contains { abs($0.time - editor.time) <= tolerance }
        return HStack(spacing: 2) {
            Color.clear.frame(width: CGFloat(depth) * 12 + 18, height: 1)
            Text(LayerProperties.title(property))
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            navButton(.keyframePrev, "Previous keyframe") {
                if let t = marks.map(\.time).filter({ $0 < editor.time - tolerance }).max() { controller.stop(); controller.seek(to: t) }
            }
            Button { controller.toggleKeyframe(property, on: layer.id) } label: {
                IconView(.keyframe, size: 12, lineWidth: here ? 3 : 1.5)
                    .foregroundStyle(here ? Theme.accent : Theme.textTertiary)
                    .frame(width: 18, height: TimelineRow.height)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(here ? "Remove the keyframe at the playhead" : "Add a keyframe at the playhead")
            navButton(.keyframeNext, "Next keyframe") {
                if let t = marks.map(\.time).filter({ $0 > editor.time + tolerance }).min() { controller.stop(); controller.seek(to: t) }
            }
        }
        .padding(.horizontal, 6)
        .background(Rectangle().fill(hovering ? Theme.rowHover : .clear))
    }

    private func navButton(_ icon: Icon, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: 11)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 14, height: TimelineRow.height)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
