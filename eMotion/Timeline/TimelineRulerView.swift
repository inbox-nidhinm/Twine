import SwiftUI
import AppKit
import MotionModel
import Theme

/// The ruler over the tracks: times with dots between, the end of the
/// composition, and the playhead's pill with the time in it. Click or drag
/// anywhere on it to scrub; drag the end line to make the scene longer or
/// shorter.
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
        view.window?.invalidateCursorRects(for: view)
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
        let mid = bounds.height / 2
        let endX = viewport.x(for: controller.duration)
        if endX < bounds.width {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.22))
            ctx.fill(CGRect(x: max(endX, 0), y: 0, width: bounds.width - max(endX, 0), height: bounds.height))
        }

        // Times at least 64 points apart, on round numbers of frames or
        // seconds, with dots between.
        let step = Self.labelStep(pointsPerSecond: viewport.pointsPerSecond, rate: rate, framesShown: controller.editor.showsFrames)
        let minor = step / 5
        var t = (viewport.start / minor).rounded(.down) * minor
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor(Theme.textTertiary),
        ]
        ctx.setFillColor(NSColor(Theme.textTertiary).withAlphaComponent(0.7).cgColor)
        while viewport.x(for: t) <= bounds.width + 40 {
            let x = viewport.x(for: t)
            let major = abs((t / step).rounded() * step - t) < minor / 10
            if t >= -1e-9 {
                if major {
                    let label = (controller.editor.showsFrames ? "\(rate.frame(at: t))" : Self.format(t)) as NSString
                    let size = label.size(withAttributes: attributes)
                    label.draw(at: CGPoint(x: x - size.width / 2, y: mid - size.height / 2), withAttributes: attributes)
                } else {
                    ctx.fillEllipse(in: CGRect(x: x - 1.25, y: mid - 1.25, width: 2.5, height: 2.5))
                }
            }
            t += minor
        }

        // The scene's end: a line to drag.
        let ex = endX.rounded() + 0.5
        ctx.setFillColor(NSColor(Theme.textTertiary).cgColor)
        ctx.fill(CGRect(x: ex - 0.5, y: 0, width: 1, height: bounds.height))

        // The playhead: its line, and a pill carrying the time.
        let px = viewport.x(for: controller.editor.time).rounded() + 0.5
        let teal = NSColor(Theme.playhead).cgColor
        ctx.setFillColor(teal)
        ctx.fill(CGRect(x: px - 0.5, y: mid, width: 1, height: bounds.height - mid))
        let time = (controller.editor.showsFrames ? "\(rate.frame(at: controller.editor.time))"
                                                   : Self.pillFormat(controller.editor.time)) as NSString
        let pillText: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = time.size(withAttributes: pillText)
        let pill = CGRect(x: px - (size.width + 22) / 2, y: mid - 11, width: size.width + 22, height: 22)
        ctx.addPath(CGPath(roundedRect: pill, cornerWidth: 11, cornerHeight: 11, transform: nil))
        ctx.fillPath()
        time.draw(at: CGPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2), withAttributes: pillText)
    }

    /// The playhead's time in its pill: seconds to two places, as `1.18`,
    /// and minutes and seconds past a minute.
    static func pillFormat(_ t: Double) -> String {
        t >= 60 ? TimeFormat.clock(t) : String(format: "%.2f", t)
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

    private var draggingEnd = false

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        let x = convert(event.locationInWindow, from: nil).x
        if abs(x - controller.editor.viewport.x(for: controller.duration)) <= 5 {
            draggingEnd = true
            controller.begin("Scene Length")
            return
        }
        controller.stop()
        scrub(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller else { return }
        if draggingEnd {
            let x = convert(event.locationInWindow, from: nil).x
            controller.setDuration(controller.editor.viewport.time(at: x))
        } else {
            scrub(event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if draggingEnd {
            draggingEnd = false
            controller?.end()
        }
    }

    override func resetCursorRects() {
        guard let controller else { return }
        let x = controller.editor.viewport.x(for: controller.duration)
        addCursorRect(CGRect(x: x - 5, y: 0, width: 10, height: bounds.height), cursor: .resizeLeftRight)
    }

    private func scrub(_ event: NSEvent) {
        guard let controller else { return }
        let x = convert(event.locationInWindow, from: nil).x
        controller.seek(to: controller.editor.viewport.time(at: x))
    }
}
