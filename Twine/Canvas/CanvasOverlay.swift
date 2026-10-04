import AppKit
import QuartzCore
import Theme

/// The selection, drawn over the canvas in view points so its lines stay one
/// point thick at any zoom: outlines, the resize handles, the anchor, the
/// hover outline, the marquee, a selected Move's path with its handles, and
/// the points of a path being drawn or edited.
///
/// Not tied to the main actor, like `CALayer` itself; the canvas only ever
/// touches it from the main thread.
nonisolated final class CanvasOverlay: CALayer {
    /// The layer under the pointer, in the selection's line and following
    /// its shape, as Figma's.
    private let hover = CAShapeLayer()
    private let outlines = CAShapeLayer()
    /// The selected shapes' own outlines, in the selection's colour, so a
    /// shape stays readable when blurred, faded or drawn in the canvas's
    /// colour.
    private let shapes = CAShapeLayer()
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
    /// Smart guides while something snaps: the lines it lines up on, and
    /// equal spaces with their lengths.
    private let guides = CAShapeLayer()
    private let gapLines = CAShapeLayer()
    private var gapLabels: [CATextLayer] = []
    /// Editing points: the path's line, the segment following the pen, the
    /// handles on their arms, and the points, selected ones filled.
    private let pathLine = CAShapeLayer()
    private let pathRubber = CAShapeLayer()
    private let pathArms = CAShapeLayer()
    private let pathHandles = CAShapeLayer()
    private let pathPoints = CAShapeLayer()
    private let pathSelected = CAShapeLayer()
    /// Cropping a picture: the whole picture, faint, in a holder of its own
    /// (the overlay sizes its sublayers to itself, and the picture has a
    /// shape of its own), its outline, and the corners that scale it.
    private let gradientShade = CAShapeLayer()
    private let gradientLine = CAShapeLayer()
    private let gradientEnds = CAShapeLayer()
    /// One dot per stop, each in its own colour.
    private let gradientStops = CALayer()
    private let cropHolder = CALayer()
    private let cropPicture = CALayer()
    private let cropLine = CAShapeLayer()
    private let cropHandles = CAShapeLayer()

    private static let accent = NSColor(Theme.accent).cgColor
    private static let handle = NSColor(Theme.handle).cgColor

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
        for l in [cropHolder, textSelection, hover, cropLine, shapes, outlines, union, marquee, motion, motionArms, anchor, handles,
                  cropHandles, motionStart, motionEnd, motionHandles, textMarked, caret, guides, gapLines,
                  pathLine, pathRubber, pathArms, pathHandles, pathPoints, pathSelected,
                  gradientShade, gradientLine, gradientEnds, gradientStops] {
            l.anchorPoint = .zero
            l.actions = Self.none
            l.contentsScale = 2
            addSublayer(l)
        }
        for l in [hover, outlines, shapes, union] {
            l.fillColor = nil
            l.strokeColor = Self.accent
            l.lineWidth = 1
        }
        marquee.fillColor = NSColor(Theme.accent).withAlphaComponent(0.08).cgColor
        marquee.strokeColor = Self.accent
        marquee.lineWidth = 1
        handles.fillColor = Self.handle
        handles.strokeColor = Self.accent
        handles.lineWidth = 1
        anchor.fillColor = Self.handle
        anchor.strokeColor = Self.accent
        anchor.lineWidth = 1
        motion.fillColor = nil
        motion.strokeColor = Self.accent
        motion.lineWidth = 1.5
        motion.lineDashPattern = [5, 4]
        motionArms.fillColor = nil
        motionArms.strokeColor = NSColor(Theme.accent).withAlphaComponent(0.6).cgColor
        motionArms.lineWidth = 1
        motionStart.fillColor = Self.handle
        motionStart.strokeColor = Self.accent
        motionStart.lineWidth = 1.5
        motionEnd.fillColor = Self.accent
        motionEnd.strokeColor = Self.handle
        motionEnd.lineWidth = 1.5
        motionHandles.fillColor = Self.handle
        motionHandles.strokeColor = Self.accent
        motionHandles.lineWidth = 1
        textSelection.fillColor = NSColor(Theme.accent).withAlphaComponent(0.3).cgColor
        textMarked.fillColor = nil
        textMarked.strokeColor = Self.accent
        textMarked.lineWidth = 1.5
        caret.fillColor = Self.accent
        for l in [pathLine, pathRubber] {
            l.fillColor = nil
            l.strokeColor = Self.accent
            l.lineWidth = 1
        }
        pathArms.fillColor = nil
        pathArms.strokeColor = NSColor(Theme.accent).withAlphaComponent(0.7).cgColor
        pathArms.lineWidth = 1
        cropPicture.anchorPoint = .zero
        cropPicture.actions = Self.none.merging(["transform": NSNull(), "opacity": NSNull()]) { a, _ in a }
        cropPicture.contentsGravity = .resize
        cropPicture.opacity = Float(Self.cropPictureOpacity)
        cropHolder.addSublayer(cropPicture)
        cropLine.fillColor = nil
        cropLine.strokeColor = Self.accent
        cropLine.lineWidth = 1
        cropLine.lineDashPattern = [4, 3]
        cropHandles.fillColor = Self.handle
        cropHandles.strokeColor = Self.accent
        cropHandles.lineWidth = 1
        pathHandles.fillColor = Self.handle
        pathHandles.strokeColor = Self.accent
        pathHandles.lineWidth = 1
        pathPoints.fillColor = Self.handle
        pathPoints.strokeColor = Self.accent
        pathPoints.lineWidth = 1.5
        pathSelected.fillColor = Self.accent
        pathSelected.strokeColor = Self.handle
        pathSelected.lineWidth = 1.5
        for l in [guides, gapLines] {
            l.fillColor = nil
            l.strokeColor = Self.guide
            l.lineWidth = 1
        }
        // The gradient's line is white over a soft dark one, so it reads on
        // any colours under it.
        gradientShade.fillColor = nil
        gradientShade.strokeColor = CGColor(gray: 0, alpha: 0.35)
        gradientShade.lineWidth = 3
        gradientLine.fillColor = nil
        gradientLine.strokeColor = Self.handle
        gradientLine.lineWidth = 1.5
        gradientEnds.fillColor = Self.handle
        gradientEnds.strokeColor = Self.accent
        gradientEnds.lineWidth = 1.5
    }

    private static let guide = NSColor(Theme.guide).cgColor

    /// An equal space: a line across it with a tick at each end, and its
    /// length in a pill beside it.
    struct GapMark {
        var from: CGPoint
        var to: CGPoint
        var label: String
    }

    func updateSnap(lines: [(CGPoint, CGPoint)], gaps: [GapMark]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let path = CGMutablePath()
        for (a, b) in lines {
            // On the half point, so a one-point line stays crisp.
            path.move(to: CGPoint(x: crisp(a.x), y: crisp(a.y)))
            path.addLine(to: CGPoint(x: crisp(b.x), y: crisp(b.y)))
        }
        guides.path = lines.isEmpty ? nil : path

        let marks = CGMutablePath()
        for gap in gaps {
            let across = abs(gap.to.x - gap.from.x) >= abs(gap.to.y - gap.from.y)
            let a = CGPoint(x: crisp(gap.from.x), y: crisp(gap.from.y)), b = CGPoint(x: crisp(gap.to.x), y: crisp(gap.to.y))
            marks.move(to: a)
            marks.addLine(to: b)
            for p in [a, b] {
                marks.move(to: across ? CGPoint(x: p.x, y: p.y - 4) : CGPoint(x: p.x - 4, y: p.y))
                marks.addLine(to: across ? CGPoint(x: p.x, y: p.y + 4) : CGPoint(x: p.x + 4, y: p.y))
            }
        }
        gapLines.path = gaps.isEmpty ? nil : marks

        while gapLabels.count < gaps.count {
            let label = CATextLayer()
            label.actions = Self.none
            label.contentsScale = 2
            label.fontSize = 10
            label.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            label.foregroundColor = NSColor(Theme.textOnColor).cgColor
            label.backgroundColor = Self.guide
            label.alignmentMode = .center
            label.cornerRadius = 3
            addSublayer(label)
            gapLabels.append(label)
        }
        for (i, label) in gapLabels.enumerated() {
            guard i < gaps.count else { label.isHidden = true; continue }
            let gap = gaps[i]
            let across = abs(gap.to.x - gap.from.x) >= abs(gap.to.y - gap.from.y)
            let width = CGFloat(gap.label.count) * 6.5 + 8
            let mid = CGPoint(x: (gap.from.x + gap.to.x) / 2, y: (gap.from.y + gap.to.y) / 2)
            label.isHidden = false
            label.string = gap.label
            // Beside the line, clear of the ticks.
            label.frame = across ? CGRect(x: mid.x - width / 2, y: mid.y + 6, width: width, height: 15)
                                 : CGRect(x: mid.x + 6, y: mid.y - 7.5, width: width, height: 15)
        }
    }

    private func crisp(_ v: CGFloat) -> CGFloat { v.rounded(.down) + 0.5 }

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

    /// A path's points being drawn or edited, all in view points.
    struct PathMarks {
        var outline: CGPath?
        var points: [CGPoint] = []
        var selected: [CGPoint] = []
        /// Each shown handle, from its point.
        var arms: [(point: CGPoint, handle: CGPoint)] = []
        /// The segment the pen would add, from the last point to the pointer.
        var rubber: CGPath?
    }

    /// How big a path's point and handle dots are drawn, as radii.
    static let pathPointRadius: CGFloat = 4
    static let pathHandleRadius: CGFloat = 3

    func updatePath(_ marks: PathMarks?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let marks else {
            for l in [pathLine, pathRubber, pathArms, pathHandles, pathPoints, pathSelected] { l.path = nil }
            return
        }
        pathLine.path = marks.outline
        pathRubber.path = marks.rubber
        let arms = CGMutablePath(), handles = CGMutablePath()
        let h = Self.pathHandleRadius
        for arm in marks.arms {
            arms.move(to: arm.point)
            arms.addLine(to: arm.handle)
            handles.addEllipse(in: CGRect(x: arm.handle.x - h, y: arm.handle.y - h, width: h * 2, height: h * 2))
        }
        pathArms.path = arms
        pathHandles.path = handles
        func dots(_ points: [CGPoint]) -> CGPath {
            let path = CGMutablePath()
            let r = Self.pathPointRadius
            for p in points { path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
            return path
        }
        pathPoints.path = dots(marks.points)
        pathSelected.path = dots(marks.selected)
    }

    /// A gradient being edited, in view points: its ends, a radial one's
    /// circle, and each stop with its colour and whether it is picked.
    struct GradientMarks {
        var start: CGPoint
        var end: CGPoint
        var circle: CGPath?
        /// A radial gradient's third handle, across its line, which sets how
        /// far its oval reaches that way.
        var across: CGPoint?
        var stops: [(point: CGPoint, color: CGColor, picked: Bool)]
    }

    static let gradientEndRadius: CGFloat = 5
    static let gradientStopRadius: CGFloat = 4.5

    func updateGradient(_ marks: GradientMarks?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let marks else {
            for l in [gradientShade, gradientLine, gradientEnds] { l.path = nil }
            gradientStops.sublayers = nil
            return
        }
        let line = CGMutablePath()
        line.move(to: marks.start)
        line.addLine(to: marks.end)
        if let circle = marks.circle { line.addPath(circle) }
        if let across = marks.across {
            line.move(to: marks.start)
            line.addLine(to: across)
        }
        gradientShade.path = line
        gradientLine.path = line
        let ends = CGMutablePath()
        let r = Self.gradientEndRadius
        for p in [marks.start, marks.end] + (marks.across.map { [$0] } ?? []) { ends.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)) }
        gradientEnds.path = ends
        // A dot per stop, kept and recoloured while their count holds.
        var dots = (gradientStops.sublayers as? [CAShapeLayer]) ?? []
        if dots.count != marks.stops.count {
            dots = marks.stops.map { _ in
                let dot = CAShapeLayer()
                dot.actions = Self.none
                dot.contentsScale = 2
                dot.shadowColor = CGColor(gray: 0, alpha: 1)
                dot.shadowOpacity = 0.4
                dot.shadowRadius = 1.5
                dot.shadowOffset = .zero
                return dot
            }
            gradientStops.sublayers = dots
        }
        // The picked stop over the others.
        for (dot, stop) in zip(dots, marks.stops) {
            let s = Self.gradientStopRadius + (stop.picked ? 1 : 0)
            dot.path = CGPath(ellipseIn: CGRect(x: stop.point.x - s, y: stop.point.y - s, width: s * 2, height: s * 2), transform: nil)
            dot.fillColor = stop.color
            dot.strokeColor = stop.picked ? Self.accent : Self.handle
            dot.lineWidth = stop.picked ? 2 : 1.5
            dot.zPosition = stop.picked ? 1 : 0
        }
    }

    /// A picture being cropped, in view points.
    struct CropMarks {
        var image: CGImage?
        /// The picture the way up it is stored, in its own pixels, and the
        /// transform carrying those pixels onto the view.
        var size: CGSize
        var transform: CATransform3D
        /// Its four corners, from its top-left clockwise.
        var corners: [CGPoint]
    }

    /// How much of the picture outside the shape shows while cropping.
    static let cropPictureOpacity = 0.35

    func updateCrop(_ marks: CropMarks?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let marks else {
            cropPicture.contents = nil
            cropPicture.isHidden = true
            cropLine.path = nil
            cropHandles.path = nil
            return
        }
        cropPicture.isHidden = false
        if (cropPicture.contents as AnyObject?) !== marks.image { cropPicture.contents = marks.image }
        cropPicture.transform = CATransform3DIdentity
        cropPicture.bounds = CGRect(origin: .zero, size: marks.size)
        cropPicture.position = .zero
        cropPicture.transform = marks.transform
        cropLine.path = polygons([marks.corners])
        let squares = CGMutablePath()
        let half = CanvasHandles.size / 2
        for p in marks.corners {
            squares.addRect(CGRect(x: (p.x - half).rounded() + 0.5, y: (p.y - half).rounded() + 0.5,
                                   width: CanvasHandles.size - 1, height: CanvasHandles.size - 1))
        }
        cropHandles.path = squares
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
        didSet { for l in sublayers ?? [] where !(l is CATextLayer) { l.frame = bounds } }
    }

    /// The selected shapes' outlines, in view points.
    func updateShapes(_ path: CGPath?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapes.path = path
        CATransaction.commit()
    }

    func update(outlines boxes: [[CGPoint]], union unionBox: [CGPoint]?, handles points: [CGPoint],
                anchor anchorPoint: CGPoint?, hover hoverPath: CGPath?, marquee rect: CGRect?,
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
        hover.path = hoverPath
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
