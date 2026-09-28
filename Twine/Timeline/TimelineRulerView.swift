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
            ctx.setFillColor(NSColor(Theme.pastTheEnd).cgColor)
            ctx.fill(CGRect(x: max(endX, 0), y: 0, width: bounds.width - max(endX, 0), height: bounds.height))
        }

        // Whole seconds (or round numbers of frames) at least 64 points
        // apart, with dots between.
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
            .foregroundColor: NSColor(Theme.textOnColor),
        ]
        let size = time.size(withAttributes: pillText)
        let pill = CGRect(x: px - (size.width + 22) / 2, y: mid - 11, width: size.width + 22, height: 22)
        pillRect = pill
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
        let secondSteps: [Double] = [1, 2, 5, 10, 15, 30, 60, 120, 300]
        let candidates = framesShown ? frameSteps + secondSteps : secondSteps
        return candidates.first { $0 >= minimum } ?? 600
    }

    static func format(_ t: Double) -> String {
        t >= 60 ? TimeFormat.clock(t) : "\(Int(t.rounded()))s"
    }

    // MARK: Scrubbing

    private var draggingEnd = false
    /// Where a press began, so a click that wobbles a point still glides
    /// rather than turning into a scrub.
    private var pressX: CGFloat?
    /// The playhead's pill as last drawn, which the hand grabs.
    private var pillRect: CGRect = .zero
    /// Holding the pill (or scrubbing from anywhere on the ruler): how far
    /// the pointer sits from the playhead, so it keeps its grip rather than
    /// the playhead jumping to the pointer.
    private var grip: CGFloat?

    private var endX: CGFloat { controller.map { $0.editor.viewport.x(for: $0.duration) } ?? -100 }

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        let p = convert(event.locationInWindow, from: nil)
        if abs(p.x - endX) <= 5 {
            draggingEnd = true
            controller.begin("Scene Length")
            window?.invalidateCursorRects(for: self)
            return
        }
        controller.stop()
        Cursors.handGrabbed.set()
        defer { window?.invalidateCursorRects(for: self) }
        if pillRect.insetBy(dx: -2, dy: -2).contains(p) {
            // The pill is held where it was grabbed and drags from there.
            grip = controller.editor.viewport.x(for: controller.editor.time) - p.x
            return
        }
        // A click elsewhere slides the playhead there; dragging on scrubs.
        pressX = p.x
        grip = 0
        controller.glide(to: controller.editor.viewport.time(at: p.x))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller else { return }
        let x = convert(event.locationInWindow, from: nil).x
        if draggingEnd {
            controller.setDuration(controller.editor.viewport.time(at: x))
        } else {
            if let start = pressX, abs(x - start) < 3 { return }
            pressX = nil
            controller.seek(to: controller.editor.viewport.time(at: x + (grip ?? 0)))
            Cursors.handGrabbed.set()
        }
    }

    override func mouseUp(with event: NSEvent) {
        pressX = nil
        grip = nil
        if draggingEnd {
            draggingEnd = false
            controller?.end()
        }
        window?.invalidateCursorRects(for: self)
        cursor(at: convert(event.locationInWindow, from: nil)).set()
    }

    // MARK: Pointers

    /// The scene's end drags sideways; the playhead's pill is a handle to
    /// grab, held while scrubbing; the rest is the app's arrow. Set on every
    /// move as well as by cursor rects, since the SwiftUI window around this
    /// view puts its own arrow back as the pointer moves.
    private func cursor(at p: CGPoint) -> NSCursor {
        if draggingEnd { return Cursors.resizeHorizontal }
        if grip != nil { return Cursors.handGrabbed }
        if abs(p.x - endX) <= 5 { return Cursors.resizeHorizontal }
        if pillRect.insetBy(dx: -2, dy: -2).contains(p) { return Cursors.hand }
        return Cursors.arrow
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .cursorUpdate, .mouseEnteredAndExited,
                                                               .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { cursor(at: convert(event.locationInWindow, from: nil)).set() }
    override func cursorUpdate(with event: NSEvent) { cursor(at: convert(event.locationInWindow, from: nil)).set() }

    override func resetCursorRects() {
        // Held, the whole ruler keeps the held pointer: the playhead moves
        // under the pointer on every step, and the zones are drawn again.
        if draggingEnd || grip != nil {
            return addCursorRect(bounds, cursor: draggingEnd ? Cursors.resizeHorizontal : Cursors.handGrabbed)
        }
        let x = endX
        addCursorRect(CGRect(x: 0, y: 0, width: max(x - 5, 0), height: bounds.height), cursor: Cursors.arrow)
        addCursorRect(CGRect(x: x + 5, y: 0, width: max(bounds.width - x - 5, 0), height: bounds.height), cursor: Cursors.arrow)
        addCursorRect(CGRect(x: x - 5, y: 0, width: 10, height: bounds.height), cursor: Cursors.resizeHorizontal)
        addCursorRect(pillRect.insetBy(dx: -2, dy: -2), cursor: Cursors.hand)
    }
}
