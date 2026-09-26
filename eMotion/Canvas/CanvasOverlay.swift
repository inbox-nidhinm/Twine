import AppKit
import QuartzCore
import Theme

/// The selection, drawn over the canvas in view points so its lines stay one
/// point thick at any zoom: outlines, the resize handles, the anchor, the
/// hover outline, the marquee, and a selected Move's path with its handles.
///
/// Not tied to the main actor, like `CALayer` itself; the canvas only ever
/// touches it from the main thread.
nonisolated final class CanvasOverlay: CALayer {
    private let hover = CAShapeLayer()
    private let outlines = CAShapeLayer()
    private let union = CAShapeLayer()
    private let handles = CAShapeLayer()
    private let anchor = CAShapeLayer()
    private let marquee = CAShapeLayer()
    private let motion = CAShapeLayer()
    private let motionArms = CAShapeLayer()
    private let motionStart = CAShapeLayer()
    private let motionEnd = CAShapeLayer()
    private let motionHandles = CAShapeLayer()
    /// Typing on the canvas: the selected letters, the half-typed ones, and
    /// the caret.
    private let textSelection = CAShapeLayer()
    private let textMarked = CAShapeLayer()
    private let caret = CAShapeLayer()

    private static let accent = NSColor(Theme.accent).cgColor

    override init() {
        super.init()
        commonInit()
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    private func commonInit() {
        anchorPoint = .zero
        actions = Self.none
        for l in [textSelection, hover, outlines, union, marquee, motion, motionArms, anchor, handles, motionStart, motionEnd,
                  motionHandles, textMarked, caret] {
            l.anchorPoint = .zero
            l.actions = Self.none
            l.contentsScale = 2
            addSublayer(l)
        }
        for l in [hover, outlines, union] {
            l.fillColor = nil
            l.strokeColor = Self.accent
            l.lineWidth = 1
        }
        hover.lineWidth = 1.5
        marquee.fillColor = NSColor(Theme.accent).withAlphaComponent(0.08).cgColor
        marquee.strokeColor = Self.accent
        marquee.lineWidth = 1
        handles.fillColor = CGColor(gray: 1, alpha: 1)
        handles.strokeColor = Self.accent
        handles.lineWidth = 1
        anchor.fillColor = CGColor(gray: 1, alpha: 1)
        anchor.strokeColor = Self.accent
        anchor.lineWidth = 1
        motion.fillColor = nil
        motion.strokeColor = Self.accent
        motion.lineWidth = 1.5
        motion.lineDashPattern = [5, 4]
        motionArms.fillColor = nil
        motionArms.strokeColor = NSColor(Theme.accent).withAlphaComponent(0.6).cgColor
        motionArms.lineWidth = 1
        motionStart.fillColor = CGColor(gray: 1, alpha: 1)
        motionStart.strokeColor = Self.accent
        motionStart.lineWidth = 1.5
        motionEnd.fillColor = Self.accent
        motionEnd.strokeColor = CGColor(gray: 1, alpha: 1)
        motionEnd.lineWidth = 1.5
        motionHandles.fillColor = CGColor(gray: 1, alpha: 1)
        motionHandles.strokeColor = Self.accent
        motionHandles.lineWidth = 1
        textSelection.fillColor = NSColor(Theme.accent).withAlphaComponent(0.3).cgColor
        textMarked.fillColor = nil
        textMarked.strokeColor = Self.accent
        textMarked.lineWidth = 1.5
        caret.fillColor = Self.accent
    }

    /// The text being typed into: its selection, half-typed input and caret,
    /// all in view points. Nil paths clear them.
    func updateText(selection: CGPath?, marked: CGPath?, caret caretPath: CGPath?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        textSelection.path = selection
        textMarked.path = marked
        caret.path = caretPath
        CATransaction.commit()
    }

    /// The caret blinks by showing and hiding.
    func showCaret(_ visible: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caret.isHidden = !visible
        CATransaction.commit()
    }

    /// A Move's path in view points: the dashed route, a hollow dot where it
    /// starts, a filled dot where it ends, and a curve's two handles.
    struct Motion {
        var start: CGPoint
        var end: CGPoint
        var startHandle: CGPoint?
        var endHandle: CGPoint?
    }

    /// How far from a motion point a click still grabs it.
    static let motionHit: CGFloat = 8

    nonisolated(unsafe) private static let none: [String: CAAction] = ["path": NSNull(), "frame": NSNull(), "bounds": NSNull(),
                                                   "position": NSNull(), "hidden": NSNull(), "contents": NSNull()]

    override var frame: CGRect {
        didSet { for l in sublayers ?? [] { l.frame = bounds } }
    }

    func update(outlines boxes: [[CGPoint]], union unionBox: [CGPoint]?, handles points: [CGPoint],
                anchor anchorPoint: CGPoint?, hover hoverBox: [CGPoint]?, marquee rect: CGRect?,
                motion route: Motion? = nil) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let route {
            let line = CGMutablePath()
            line.move(to: route.start)
            if let a = route.startHandle, let b = route.endHandle {
                line.addCurve(to: route.end, control1: a, control2: b)
                let arms = CGMutablePath()
                arms.move(to: route.start); arms.addLine(to: a)
                arms.move(to: route.end); arms.addLine(to: b)
                motionArms.path = arms
                let diamonds = CGMutablePath()
                for p in [a, b] {
                    diamonds.addLines(between: [CGPoint(x: p.x, y: p.y - 5), CGPoint(x: p.x + 5, y: p.y),
                                                CGPoint(x: p.x, y: p.y + 5), CGPoint(x: p.x - 5, y: p.y)])
                    diamonds.closeSubpath()
                }
                motionHandles.path = diamonds
            } else {
                line.addLine(to: route.end)
                motionArms.path = nil
                motionHandles.path = nil
            }
            motion.path = line
            motionStart.path = CGPath(ellipseIn: CGRect(x: route.start.x - 5, y: route.start.y - 5, width: 10, height: 10), transform: nil)
            motionEnd.path = CGPath(ellipseIn: CGRect(x: route.end.x - 5.5, y: route.end.y - 5.5, width: 11, height: 11), transform: nil)
        } else {
            for l in [motion, motionArms, motionStart, motionEnd, motionHandles] { l.path = nil }
        }

        outlines.path = polygons(boxes)
        union.path = unionBox.map { polygons([$0]) } ?? nil
        hover.path = hoverBox.map { polygons([$0]) } ?? nil
        marquee.path = rect.map { CGPath(rect: $0.integral.insetBy(dx: 0.5, dy: 0.5), transform: nil) }

        let squares = CGMutablePath()
        let half = CanvasHandles.size / 2
        for p in points {
            // On whole points, so the one-point outline stays crisp.
            squares.addRect(CGRect(x: (p.x - half).rounded() + 0.5, y: (p.y - half).rounded() + 0.5,
                                   width: CanvasHandles.size - 1, height: CanvasHandles.size - 1))
        }
        handles.path = squares

        if let a = anchorPoint {
            let marker = CGMutablePath()
            marker.addEllipse(in: CGRect(x: a.x - 3.5, y: a.y - 3.5, width: 7, height: 7))
            marker.move(to: CGPoint(x: a.x - 7, y: a.y))
            marker.addLine(to: CGPoint(x: a.x - 3.5, y: a.y))
            marker.move(to: CGPoint(x: a.x + 3.5, y: a.y))
            marker.addLine(to: CGPoint(x: a.x + 7, y: a.y))
            marker.move(to: CGPoint(x: a.x, y: a.y - 7))
            marker.addLine(to: CGPoint(x: a.x, y: a.y - 3.5))
            marker.move(to: CGPoint(x: a.x, y: a.y + 3.5))
            marker.addLine(to: CGPoint(x: a.x, y: a.y + 7))
            anchor.path = marker
        } else {
            anchor.path = nil
        }
    }

    private func polygons(_ boxes: [[CGPoint]]) -> CGPath {
        let path = CGMutablePath()
        for box in boxes where box.count > 1 {
            path.addLines(between: box)
            path.closeSubpath()
        }
        return path
    }
}
