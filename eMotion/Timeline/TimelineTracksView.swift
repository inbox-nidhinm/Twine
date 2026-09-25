import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import Theme

/// The timeline's tracks, drawn and handled in AppKit for exact positions:
/// a bar per layer from its in point to its out point, the keyframes of its
/// open properties, and the playhead.
struct TimelineTracks: NSViewRepresentable {
    let controller: EditorController
    let editor: EditorModel
    let rows: [TimelineRow]

    func makeNSView(context: Context) -> TimelineTracksView {
        let view = TimelineTracksView(frame: .zero)
        view.controller = controller
        return view
    }

    func updateNSView(_ view: TimelineTracksView, context: Context) {
        // Read here so SwiftUI redraws the tracks when any of them change.
        _ = (editor.time, editor.selection, editor.selectedKeyframes, editor.viewport.pointsPerSecond,
             editor.viewport.start, controller.project.composition)
        view.rows = rows
        view.needsDisplay = true
    }
}

final class TimelineTracksView: NSView {
    var controller: EditorController?
    var rows: [TimelineRow] = []

    private var drag: Drag?
    /// How near, in points, a dragged time jumps to something worth lining up with.
    static let snapDistance: Double = 6
    static let keyframeHit: Double = 6
    static let edgeHit: Double = 5

    private enum Drag {
        case keyframes(originals: [KeyframeRef: Double], anchor: Double, startX: Double, layers: [Layer])
        case bars(layers: [Layer], startX: Double, anchor: Double)
        case trimIn(Layer, startX: Double)
        case trimOut(Layer, startX: Double)
        case marquee(start: CGPoint, current: CGPoint, base: Set<KeyframeRef>)
    }

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

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let viewport, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let h = TimelineRow.height
        let duration = controller.duration

        // After the composition ends, dimmed.
        let endX = viewport.x(for: duration)
        if endX < bounds.width {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.22))
            ctx.fill(CGRect(x: max(endX, 0), y: 0, width: bounds.width - max(endX, 0), height: bounds.height))
        }

        let selectedKeys = controller.selectedKeyframes
        for (index, row) in rows.enumerated() {
            let y = CGFloat(index) * h
            ctx.setFillColor(NSColor(Theme.border).withAlphaComponent(0.5).cgColor)
            ctx.fill(CGRect(x: 0, y: y + h - 1, width: bounds.width, height: 1))

            switch row.kind {
            case .layer(let layer, _):
                drawBar(layer, y: y, in: ctx, viewport: viewport,
                        selected: controller.editor.selection.contains(layer.id),
                        summary: !controller.editor.timelineExpanded.contains(layer.id))
            case .property(let layer, let property, _):
                guard let marks = LayerProperties.get(property, of: layer)?.marks else { continue }
                let mid = y + h / 2
                // A thin line under each segment says there is motion there.
                ctx.setFillColor(NSColor(Theme.textTertiary).withAlphaComponent(0.35).cgColor)
                for (a, b) in zip(marks, marks.dropFirst()) {
                    let x0 = viewport.x(for: a.time), x1 = viewport.x(for: b.time)
                    ctx.fill(CGRect(x: x0, y: mid - 0.5, width: max(x1 - x0, 0), height: 1))
                }
                for mark in marks {
                    let ref = KeyframeRef(layerID: layer.id, property: property, keyframeID: mark.id)
                    drawKeyframe(mark, at: CGPoint(x: viewport.x(for: mark.time), y: mid), size: 9,
                                 selected: selectedKeys.contains(ref), in: ctx)
                }
            }
        }

        // The playhead.
        let px = viewport.x(for: controller.editor.time).rounded() + 0.5
        ctx.setFillColor(NSColor(Theme.accent).cgColor)
        ctx.fill(CGRect(x: px - 0.5, y: 0, width: 1, height: bounds.height))

        if case .marquee(let a, let b, _) = drag {
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            ctx.setFillColor(NSColor(Theme.accent).withAlphaComponent(0.1).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor(Theme.accent).cgColor)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1)
        }
    }

    private func barRect(_ layer: Layer, y: CGFloat, viewport: TimelineViewport) -> CGRect {
        let x0 = viewport.x(for: layer.inPoint), x1 = viewport.x(for: layer.outPoint)
        return CGRect(x: x0, y: y + 4, width: max(x1 - x0, 2), height: TimelineRow.height - 8)
    }

    private func drawBar(_ layer: Layer, y: CGFloat, in ctx: CGContext, viewport: TimelineViewport,
                         selected: Bool, summary: Bool) {
        let rect = barRect(layer, y: y, viewport: viewport)
        let path = CGPath(roundedRect: rect, cornerWidth: Theme.radiusRow, cornerHeight: Theme.radiusRow, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(selected ? Theme.rowSelected : Theme.panelRaised).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(selected ? Theme.accent : Theme.edge).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        // A shut layer shows where its keyframes are, all properties at once.
        guard summary else { return }
        let times = Set(Keyframing.allMarks(of: layer).map { ($0.1.time * 1000).rounded() / 1000 })
        for t in times {
            drawKeyframe(KeyframeMark(id: UUID(), time: t, easing: .linear),
                         at: CGPoint(x: viewport.x(for: t), y: y + TimelineRow.height / 2), size: 7,
                         selected: false, in: ctx, muted: true)
        }
    }

    /// A diamond for a curve, a square for a hold, a circle for a spring.
    private func drawKeyframe(_ mark: KeyframeMark, at p: CGPoint, size: CGFloat, selected: Bool,
                              in ctx: CGContext, muted: Bool = false) {
        let r = size / 2
        let path = CGMutablePath()
        switch mark.easing {
        case .hold:
            path.addRect(CGRect(x: p.x - r * 0.8, y: p.y - r * 0.8, width: r * 1.6, height: r * 1.6))
        case .spring:
            path.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: size, height: size))
        default:
            path.addLines(between: [CGPoint(x: p.x, y: p.y - r), CGPoint(x: p.x + r, y: p.y),
                                    CGPoint(x: p.x, y: p.y + r), CGPoint(x: p.x - r, y: p.y)])
            path.closeSubpath()
        }
        ctx.addPath(path)
        let fill: Color = selected ? Theme.accent : muted ? Theme.textTertiary : Theme.textSecondary
        ctx.setFillColor(NSColor(fill).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(Theme.canvas).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    // MARK: Hit testing

    private func row(at y: CGFloat) -> TimelineRow? {
        let i = Int(y / TimelineRow.height)
        return rows.indices.contains(i) ? rows[i] : nil
    }

    /// The keyframes under a point: the one on a property row, or on a shut
    /// layer's bar every keyframe at that time.
    private func keyframes(at p: CGPoint) -> [KeyframeRef] {
        guard let viewport, let row = row(at: p.y) else { return [] }
        switch row.kind {
        case .property(let layer, let property, _):
            let marks = LayerProperties.get(property, of: layer)?.marks ?? []
            guard let hit = marks.min(by: { abs(viewport.x(for: $0.time) - p.x) < abs(viewport.x(for: $1.time) - p.x) }),
                  abs(viewport.x(for: hit.time) - p.x) <= Self.keyframeHit else { return [] }
            return [KeyframeRef(layerID: layer.id, property: property, keyframeID: hit.id)]
        case .layer(let layer, _):
            guard controller?.editor.timelineExpanded.contains(layer.id) == false else { return [] }
            let all = Keyframing.allMarks(of: layer)
            guard let hit = all.min(by: { abs(viewport.x(for: $0.1.time) - p.x) < abs(viewport.x(for: $1.1.time) - p.x) }),
                  abs(viewport.x(for: hit.1.time) - p.x) <= Self.keyframeHit else { return [] }
            return all.filter { abs($0.1.time - hit.1.time) < 1e-6 }
                .map { KeyframeRef(layerID: layer.id, property: $0.0, keyframeID: $0.1.id) }
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let controller, let viewport else { return }
        window?.makeFirstResponder(self)
        controller.editor.focus = .timeline
        let p = convert(event.locationInWindow, from: nil)
        let shift = event.modifierFlags.contains(.shift)

        // A bar's ends come before the keyframes drawn on it: a layer's first
        // keyframe very often sits exactly at its in point, and on a shut row
        // it would otherwise make the end impossible to grab. Opening the row
        // reaches the keyframe.
        if let row = row(at: p.y), case .layer(let layer, _) = row.kind {
            let rect = barRect(layer, y: CGFloat(rows.firstIndex { $0.id == row.id } ?? 0) * TimelineRow.height, viewport: viewport)
            let nearIn = abs(p.x - rect.minX) <= Self.edgeHit, nearOut = abs(p.x - rect.maxX) <= Self.edgeHit
            if nearIn || nearOut {
                if !controller.editor.selection.contains(layer.id) { controller.select([layer.id]) }
                drag = nearIn ? .trimIn(layer, startX: p.x) : .trimOut(layer, startX: p.x)
                controller.begin(nearIn ? "Trim In Point" : "Trim Out Point")
                return
            }
        }

        let hits = keyframes(at: p)
        if !hits.isEmpty {
            var selection = controller.selectedKeyframes
            let allSelected = hits.allSatisfy(selection.contains)
            if shift {
                if allSelected { selection.subtract(hits) } else { selection.formUnion(hits) }
            } else if !allSelected {
                selection = Set(hits)
            }
            controller.editor.selectedKeyframes = selection
            guard !shift || !allSelected else { return needsDisplay = true }
            // Drag everything selected, measured from the keyframe grabbed.
            var originals: [KeyframeRef: Double] = [:]
            for ref in selection {
                guard let layer = controller.project.layer(withID: ref.layerID),
                      let mark = LayerProperties.get(ref.property, of: layer)?.marks.first(where: { $0.id == ref.keyframeID })
                else { continue }
                originals[ref] = mark.time
            }
            let layers = Set(selection.map(\.layerID)).compactMap(controller.project.layer(withID:))
            let anchor = hits.first.flatMap { originals[$0] } ?? viewport.time(at: p.x)
            drag = .keyframes(originals: originals, anchor: anchor, startX: p.x, layers: layers)
            controller.begin(selection.count == 1 ? "Move Keyframe" : "Move Keyframes")
            return
        }

        if let row = row(at: p.y), case .layer(let layer, _) = row.kind {
            let rect = barRect(layer, y: CGFloat(rows.firstIndex { $0.id == row.id } ?? 0) * TimelineRow.height, viewport: viewport)
            if !controller.editor.selection.contains(layer.id) || !shift {
                controller.select([layer.id], extending: shift)
            }
            if rect.contains(p) {
                let moving = controller.topmost(controller.selectedLayers)
                drag = .bars(layers: moving, startX: p.x, anchor: layer.inPoint)
                controller.begin(moving.count == 1 ? "Move Layer in Time" : "Move Layers in Time")
                return
            }
        }

        drag = .marquee(start: p, current: p, base: shift ? controller.selectedKeyframes : [])
        if !shift { controller.editor.selectedKeyframes = [] }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller, let viewport, let drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        let rate = controller.frameRate

        switch drag {
        case .keyframes(let originals, let anchor, let startX, let layers):
            let excluded = Set(originals.keys)
            let target = snapped(anchor + (p.x - startX) / viewport.pointsPerSecond, excludingKeyframes: excluded)
            let delta = rate.snapped(target) - anchor
            let times = originals.mapValues { $0 + delta }
            controller.update(layers.map { Keyframing.retime(times, in: $0) })

        case .bars(let layers, let startX, let anchor):
            let excluded = Set(layers.map(\.id))
            let target = snapped(anchor + (p.x - startX) / viewport.pointsPerSecond, excludingLayers: excluded)
            let delta = rate.snapped(target) - anchor
            controller.update(layers.map { $0.shiftedInTime(by: delta) })

        case .trimIn(let layer, _):
            var edited = layer
            let t = rate.snapped(snapped(viewport.time(at: p.x), excludingLayers: [layer.id]))
            edited.inPoint = min(t, layer.outPoint - rate.frameDuration)
            controller.update([edited])

        case .trimOut(let layer, _):
            var edited = layer
            let t = rate.snapped(snapped(viewport.time(at: p.x), excludingLayers: [layer.id]))
            edited.outPoint = max(t, layer.inPoint + rate.frameDuration)
            controller.update([edited])

        case .marquee(let start, _, let base):
            self.drag = .marquee(start: start, current: p, base: base)
            let rect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            controller.editor.selectedKeyframes = base.union(keyframes(in: rect))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let controller, let drag else { return }
        self.drag = nil
        switch drag {
        case .keyframes, .bars, .trimIn, .trimOut: controller.end()
        case .marquee: break
        }
        needsDisplay = true
    }

    private func keyframes(in rect: CGRect) -> Set<KeyframeRef> {
        guard let viewport else { return [] }
        var found = Set<KeyframeRef>()
        for (index, row) in rows.enumerated() {
            let mid = CGFloat(index) * TimelineRow.height + TimelineRow.height / 2
            guard mid >= rect.minY, mid <= rect.maxY else { continue }
            switch row.kind {
            case .property(let layer, let property, _):
                for mark in LayerProperties.get(property, of: layer)?.marks ?? [] where rect.minX...rect.maxX ~= viewport.x(for: mark.time) {
                    found.insert(KeyframeRef(layerID: layer.id, property: property, keyframeID: mark.id))
                }
            case .layer(let layer, _):
                guard controller?.editor.timelineExpanded.contains(layer.id) == false else { continue }
                for (property, mark) in Keyframing.allMarks(of: layer) where rect.minX...rect.maxX ~= viewport.x(for: mark.time) {
                    found.insert(KeyframeRef(layerID: layer.id, property: property, keyframeID: mark.id))
                }
            }
        }
        return found
    }

    /// Pulls a time onto the playhead, a keyframe or a layer's end when it is
    /// within a few points of one.
    private func snapped(_ time: Double, excludingKeyframes: Set<KeyframeRef> = [], excludingLayers: Set<UUID> = []) -> Double {
        guard let controller, let viewport else { return time }
        var targets: [Double] = [controller.editor.time, 0, controller.duration]
        for layer in controller.project.allLayers where !excludingLayers.contains(layer.id) {
            targets += [layer.inPoint, layer.outPoint]
            for (property, mark) in Keyframing.allMarks(of: layer)
            where !excludingKeyframes.contains(KeyframeRef(layerID: layer.id, property: property, keyframeID: mark.id)) {
                targets.append(mark.time)
            }
        }
        let reach = Self.snapDistance / viewport.pointsPerSecond
        guard let nearest = targets.min(by: { abs($0 - time) < abs($1 - time) }), abs(nearest - time) <= reach else { return time }
        return nearest
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
            // Up and down belong to the scroll view around the rows.
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
        } else if event.keyCode == 53 {
            if drag != nil {
                controller.cancel()
                drag = nil
            } else {
                controller.editor.selectedKeyframes = []
            }
            needsDisplay = true
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
