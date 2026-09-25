import AppKit
import QuartzCore
import Theme

/// The selection, drawn over the canvas in view points so its lines stay one
/// point thick at any zoom: outlines, the resize handles, the anchor, the
/// hover outline, and the marquee.
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
        for l in [hover, outlines, union, marquee, anchor, handles] {
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
    }

    nonisolated(unsafe) private static let none: [String: CAAction] = ["path": NSNull(), "frame": NSNull(), "bounds": NSNull(),
                                                   "position": NSNull(), "hidden": NSNull(), "contents": NSNull()]

    override var frame: CGRect {
        didSet { for l in sublayers ?? [] { l.frame = bounds } }
    }

    func update(outlines boxes: [[CGPoint]], union unionBox: [CGPoint]?, handles points: [CGPoint],
                anchor anchorPoint: CGPoint?, hover hoverBox: [CGPoint]?, marquee rect: CGRect?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

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
