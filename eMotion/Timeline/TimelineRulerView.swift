import SwiftUI
import AppKit
import MotionModel
import Theme

/// The ruler over the tracks: ticks and times, the end of the composition,
/// and the playhead's head. Click or drag anywhere on it to scrub.
struct TimelineRuler: NSViewRepresentable {
    let controller: EditorController
    let editor: EditorModel

    func makeNSView(context: Context) -> TimelineRulerView {
        let view = TimelineRulerView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ view: TimelineRulerView, context: Context) {
        _ = (editor.time, editor.showsFrames, editor.viewport.pointsPerSecond, editor.viewport.start,
             controller.project.composition)
        view.needsDisplay = true
    }
}

final class TimelineRulerView: NSView {
    var controller: EditorController?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let viewport = controller.editor.viewport
        let rate = controller.frameRate
        let endX = viewport.x(for: controller.duration)
        if endX < bounds.width {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.22))
            ctx.fill(CGRect(x: max(endX, 0), y: 0, width: bounds.width - max(endX, 0), height: bounds.height))
        }

        // Labels at least 64 points apart, on round numbers of frames or
        // seconds, with small ticks between.
        let step = Self.labelStep(pointsPerSecond: viewport.pointsPerSecond, rate: rate, framesShown: controller.editor.showsFrames)
        let minor = step / 5
        let first = (viewport.start / minor).rounded(.down) * minor
        var t = first
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor(Theme.textTertiary),
        ]
        ctx.setFillColor(NSColor(Theme.textTertiary).withAlphaComponent(0.6).cgColor)
        while viewport.x(for: t) <= bounds.width {
            let x = viewport.x(for: t).rounded() + 0.5
            let major = abs((t / step).rounded() * step - t) < minor / 10
            if t >= -1e-9 {
                ctx.fill(CGRect(x: x - 0.5, y: bounds.height - (major ? 8 : 4), width: 1, height: major ? 8 : 4))
                if major {
                    let label = controller.editor.showsFrames ? "\(rate.frame(at: t))" : Self.format(t)
                    (label as NSString).draw(at: CGPoint(x: x + 3, y: 3), withAttributes: attributes)
                }
            }
            t += minor
        }

        // The playhead's head, a tab on the line through the tracks.
        let px = viewport.x(for: controller.editor.time).rounded() + 0.5
        let head = CGRect(x: px - 5, y: bounds.height - 12, width: 10, height: 12)
        ctx.setFillColor(NSColor(Theme.accent).cgColor)
        ctx.addPath(CGPath(roundedRect: head, cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.fillPath()
    }

    static func labelStep(pointsPerSecond: Double, rate: FrameRate, framesShown: Bool) -> Double {
        let minimum = 64 / pointsPerSecond
        let frame = rate.frameDuration
        let frameSteps = [1.0, 2, 5, 10, 15, 30].map { $0 * frame }
        let secondSteps = [0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        let candidates = framesShown ? frameSteps + secondSteps : [frame] + secondSteps
        return candidates.first { $0 >= minimum } ?? 600
    }

    static func format(_ t: Double) -> String {
        if t >= 60 { return TimeFormat.clock(t) }
        if abs(t - t.rounded()) < 1e-6 { return "\(Int(t.rounded()))s" }
        return String(format: "%.2fs", t).replacingOccurrences(of: "0s", with: "s")
    }

    // MARK: Scrubbing

    override func mouseDown(with event: NSEvent) {
        controller?.stop()
        scrub(event)
    }

    override func mouseDragged(with event: NSEvent) {
        scrub(event)
    }

    private func scrub(_ event: NSEvent) {
        guard let controller else { return }
        let x = convert(event.locationInWindow, from: nil).x
        controller.seek(to: controller.editor.viewport.time(at: x))
    }
}
