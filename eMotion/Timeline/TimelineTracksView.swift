import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import Theme

/// The area under the ruler, drawn in AppKit for exact positions: the end of
/// the composition and the playhead. Action rows arrive in redesign
/// milestone 4.
struct TimelineTracks: NSViewRepresentable {
    let controller: EditorController
    let editor: EditorModel

    func makeNSView(context: Context) -> TimelineTracksView {
        let view = TimelineTracksView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ view: TimelineTracksView, context: Context) {
        // Read here so SwiftUI redraws the tracks when any of them change.
        _ = (editor.time, editor.viewport.pointsPerSecond, editor.viewport.start, controller.project.composition)
        view.needsDisplay = true
    }
}

final class TimelineTracksView: NSView {
    var controller: EditorController?

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var viewport: TimelineViewport? { controller?.editor.viewport }

    override func layout() {
        super.layout()
        fitIfNeeded()
    }

    /// The whole composition across the tracks at first sight.
    private func fitIfNeeded() {
        guard let viewport, let controller, !viewport.hasFitted, bounds.width > 40 else { return }
        viewport.pointsPerSecond = max((bounds.width - 24) / max(controller.duration, 0.1), 1)
        viewport.start = -8 / viewport.pointsPerSecond
        viewport.hasFitted = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let viewport, let ctx = NSGraphicsContext.current?.cgContext else { return }
        // After the composition ends, dimmed.
        let endX = viewport.x(for: controller.duration)
        if endX < bounds.width {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.22))
            ctx.fill(CGRect(x: max(endX, 0), y: 0, width: bounds.width - max(endX, 0), height: bounds.height))
        }
        let px = viewport.x(for: controller.editor.time).rounded() + 0.5
        ctx.setFillColor(NSColor(Theme.accent).cgColor)
        ctx.fill(CGRect(x: px - 0.5, y: 0, width: 1, height: bounds.height))
    }

    override func mouseDown(with event: NSEvent) {
        controller?.editor.focus = .timeline
        window?.makeFirstResponder(self)
    }

    // MARK: Zoom and scroll

    override func scrollWheel(with event: NSEvent) {
        guard let viewport else { return super.scrollWheel(with: event) }
        let x = convert(event.locationInWindow, from: nil).x
        if event.modifierFlags.contains(.command) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            zoom(by: exp(delta * 0.01), around: x)
        } else if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            viewport.start -= event.scrollingDeltaX / viewport.pointsPerSecond
            needsDisplay = true
        } else {
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil).x)
    }

    private func zoom(by factor: Double, around x: Double) {
        guard let viewport else { return }
        let t = viewport.time(at: x)
        viewport.pointsPerSecond = min(max(viewport.pointsPerSecond * factor, 5), 20_000)
        viewport.start = t - x / viewport.pointsPerSecond
        needsDisplay = true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        if event.keyCode == 51 || event.keyCode == 117 {
            controller.deleteSelection()
        } else if !PlaybackKeys.handle(event, controller) {
            super.keyDown(with: event)
        }
    }
}

/// The playback keys, shared by the canvas and the timeline.
enum PlaybackKeys {
    /// Space plays and pauses, `[` and `]` step a frame, and Home and End
    /// (or Shift with the brackets) go to the ends.
    static func handle(_ event: NSEvent, _ controller: EditorController) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        guard flags.isEmpty else { return false }
        switch event.keyCode {
        case 49: controller.togglePlay(); return true            // space
        case 115: controller.jumpToStart(); return true          // home
        case 119: controller.jumpToEnd(); return true            // end
        default: break
        }
        switch event.charactersIgnoringModifiers {
        case "[": controller.step(-1)
        case "]": controller.step(1)
        case "{": controller.jumpToStart()
        case "}": controller.jumpToEnd()
        default: return false
        }
        return true
    }
}
