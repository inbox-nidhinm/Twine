import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import Theme

/// The rows under the ruler, in a scroll view of their own so the ruler and
/// the transport stay put while a long list of actions scrolls.
struct ActionTimeline: NSViewRepresentable {
    let controller: EditorController
    let editor: EditorModel

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        let tracks = TimelineTracksView(frame: .zero)
        tracks.controller = controller
        tracks.autoresizingMask = [.width]
        scroll.documentView = tracks
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tracks = scroll.documentView as? TimelineTracksView else { return }
        // Read here so SwiftUI calls this whenever any of them change.
        _ = (editor.time, editor.selection, editor.selectedActions, editor.timelineOnlySelected,
             editor.viewport.pointsPerSecond, editor.viewport.start, controller.project)
        tracks.reload()
    }
}

/// Every action as a bar on its own row, with its layer's name on a divider
/// above its group, drawn and handled in AppKit for exact positions.
///
/// Drag a bar to move it in time, and onto another of its layer's rows to
/// reorder. Drag an end to change its length (Option for both ends). Click,
/// Shift- or Command-click, or drag a box to select. Click an eye to switch
/// an action off. Double-click a bar to rename it. Option-drag empty space,
/// or scroll sideways, to pan; Command-scroll or pinch to zoom.
final class TimelineTracksView: NSView, NSTextFieldDelegate {
    var controller: EditorController?
    private(set) var rows: [TimelineRow] = []

    private var drag: Drag?
    private var lastSelection: Set<UUID> = []
    private var renaming: (id: UUID, field: NSTextField)?

    /// How near, in points, a dragged time jumps to something worth lining up with.
    static let snapDistance = 6.0
    static let edgeHit = 5.0
    static let instantWidth = 12.0

    private enum Drag {
        case move(originals: [Action], anchor: Action, startX: Double)
        case trim(original: Action, startEdge: Bool, startX: Double)
        case marquee(start: CGPoint, current: CGPoint, base: Set<UUID>)
        case pan(startX: Double, startTime: Double)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var viewport: TimelineViewport? { controller?.editor.viewport }
    private let gutter = TimelineRow.gutter

    private func x(for time: Double) -> Double { gutter + (viewport?.x(for: time) ?? 0) }
    private func time(at x: Double) -> Double { viewport?.time(at: x - gutter) ?? 0 }

    // MARK: Rows

    func reload() {
        guard let controller else { return }
        let editor = controller.editor
        rows = TimelineRow.rows(of: controller.project, only: editor.timelineOnlySelected ? editor.selection : nil)
        sizeToRows()
        // A selection made elsewhere (the layers panel, the canvas) brings
        // its rows into view.
        if editor.selection != lastSelection {
            lastSelection = editor.selection
            if editor.focus != .timeline { scrollToRows(of: editor.selection) }
        }
        needsDisplay = true
    }

    private func sizeToRows() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let height = max(rows.last.map { $0.y + $0.height } ?? 0, clip.bounds.height)
        let size = NSSize(width: clip.bounds.width, height: height)
        if frame.size != size { setFrameSize(size) }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        sizeToRows()
    }

    private func scrollToRows(of layers: Set<UUID>) {
        let mine = rows.filter { layers.contains($0.layerID) }
        guard let first = mine.first, let last = mine.last else { return }
        scrollToVisible(CGRect(x: 0, y: first.y, width: 1, height: last.y + last.height - first.y))
    }

    private func row(at y: CGFloat) -> TimelineRow? {
        rows.first { y >= $0.y && y < $0.y + $0.height }
    }

    private func barRect(_ action: Action, in row: TimelineRow) -> CGRect {
        let x0 = x(for: action.start)
        if action.isInstant {
            return CGRect(x: x0 - Self.instantWidth / 2, y: row.y + 6, width: Self.instantWidth, height: row.height - 12)
        }
        return CGRect(x: x0, y: row.y + 3, width: max(x(for: action.end) - x0, 4), height: row.height - 6)
    }

    override func layout() {
        super.layout()
        fitIfNeeded()
    }

    /// The whole composition across the tracks at first sight.
    private func fitIfNeeded() {
        guard let viewport, let controller, !viewport.hasFitted, bounds.width - gutter > 40 else { return }
        viewport.pointsPerSecond = max((bounds.width - gutter - 24) / max(controller.duration, 0.1), 1)
        viewport.start = -8 / viewport.pointsPerSecond
        viewport.hasFitted = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let selectedLayers = controller.editor.selection
        let selectedActions = Set(controller.selectedActions.map(\.id))

        for row in rows where row.y + row.height >= dirtyRect.minY && row.y <= dirtyRect.maxY {
            switch row.kind {
            case .layer(let layer):
                drawDivider(layer, row, selected: selectedLayers.contains(layer.id), in: ctx)
            case .action(let action, let layerName):
                drawAction(action, layerName: layerName, row: row, layerSelected: selectedLayers.contains(action.targetLayerID),
                           selected: selectedActions.contains(action.id), in: ctx)
            }
        }

        // After the composition ends, dimmed.
        let endX = x(for: controller.duration)
        if endX < bounds.width {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.22))
            ctx.fill(CGRect(x: max(endX, gutter), y: 0, width: bounds.width - max(endX, gutter), height: bounds.height))
        }
        ctx.setFillColor(NSColor(Theme.border).cgColor)
        ctx.fill(CGRect(x: gutter - 1, y: 0, width: 1, height: bounds.height))

        let px = x(for: controller.editor.time).rounded() + 0.5
        if px >= gutter {
            ctx.setFillColor(NSColor(Theme.accent).cgColor)
            ctx.fill(CGRect(x: px - 0.5, y: 0, width: 1, height: bounds.height))
        }

        if case .marquee(let a, let b, _) = drag {
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            ctx.setFillColor(NSColor(Theme.accent).withAlphaComponent(0.1).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(NSColor(Theme.accent).cgColor)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5), width: 1)
        }
    }

    private func drawDivider(_ layer: Layer, _ row: TimelineRow, selected: Bool, in ctx: CGContext) {
        let rect = CGRect(x: 0, y: row.y, width: bounds.width, height: row.height)
        ctx.setFillColor(NSColor(Theme.canvas).withAlphaComponent(0.6).cgColor)
        ctx.fill(rect)
        ctx.setFillColor(NSColor(Theme.border).cgColor)
        ctx.fill(CGRect(x: 0, y: row.y, width: bounds.width, height: 1))
        drawIcon(layer.icon, in: CGRect(x: gutter + 6, y: row.y + 4, width: 12, height: 12),
                 color: NSColor(selected ? Theme.textPrimary : Theme.textTertiary), in: ctx)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor(selected ? Theme.textPrimary : Theme.textSecondary),
        ]
        (layer.name as NSString).draw(at: CGPoint(x: gutter + 24, y: row.y + 4), withAttributes: attributes)
    }

    private func drawAction(_ action: Action, layerName: String, row: TimelineRow, layerSelected: Bool,
                            selected: Bool, in ctx: CGContext) {
        if layerSelected {
            ctx.setFillColor(NSColor(Theme.rowHover).cgColor)
            ctx.fill(CGRect(x: 0, y: row.y, width: bounds.width, height: row.height))
        }
        ctx.setFillColor(NSColor(Theme.border).withAlphaComponent(0.4).cgColor)
        ctx.fill(CGRect(x: 0, y: row.y + row.height - 1, width: bounds.width, height: 1))

        // The eye in the gutter.
        drawIcon(action.isEnabled ? .eye : .eyeSlash,
                 in: CGRect(x: (gutter - 14) / 2, y: row.y + (row.height - 14) / 2, width: 14, height: 14),
                 color: NSColor(action.isEnabled ? Theme.textSecondary : Theme.textTertiary), in: ctx)

        let rect = barRect(action, in: row)
        ctx.saveGState()
        ctx.setAlpha(action.isEnabled ? 1 : 0.4)
        let path = CGPath(roundedRect: rect, cornerWidth: Theme.radiusRow, cornerHeight: Theme.radiusRow, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(selected ? Theme.rowSelected : Theme.panelRaised).cgColor)
        ctx.fillPath()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(selected ? Theme.accent : Theme.edge).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()

        // Icon, name and layer: inside a bar, or beside an instant marker.
        let label = action.isInstant
            ? CGRect(x: rect.maxX + 4, y: row.y, width: 400, height: row.height)
            : CGRect(x: rect.minX, y: row.y, width: rect.width, height: row.height)
        ctx.clip(to: label.intersection(CGRect(x: gutter, y: row.y, width: bounds.width - gutter, height: row.height)))
        var cursor = label.minX + (action.isInstant ? 0 : 5)
        drawIcon(action.spec.kind.icon, in: CGRect(x: cursor, y: row.y + (row.height - 12) / 2, width: 12, height: 12),
                 color: NSColor(selected ? Theme.textPrimary : Theme.textSecondary), in: ctx)
        cursor += 16
        let nameAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(Theme.textPrimary),
        ]
        let name = action.name as NSString
        name.draw(at: CGPoint(x: cursor, y: row.y + 5), withAttributes: nameAttributes)
        cursor += name.size(withAttributes: nameAttributes).width + 6
        (layerName as NSString).draw(at: CGPoint(x: cursor, y: row.y + 5), withAttributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor(Theme.textTertiary),
        ])
        ctx.restoreGState()
    }

    private func drawIcon(_ icon: Icon, in rect: CGRect, color: NSColor, in ctx: CGContext) {
        ctx.addPath(IconShape(icon: icon).path(in: rect).cgPath)
        ctx.setFillColor(color.cgColor)
        ctx.fillPath()
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        guard let controller else { return }
        endRename(commit: true)
        window?.makeFirstResponder(self)
        controller.editor.focus = .timeline
        let p = convert(event.locationInWindow, from: nil)
        let flags = event.modifierFlags
        let extending = flags.contains(.shift) || flags.contains(.command)

        guard let row = row(at: p.y) else { return startEmptyDrag(at: p, event: event) }
        switch row.kind {
        case .layer(let layer):
            controller.deselectActions()
            controller.select([layer.id])
        case .action(let action, _):
            if p.x < gutter { return controller.toggleEnabled(action) }
            let rect = barRect(action, in: row)
            guard rect.insetBy(dx: -Self.edgeHit, dy: 0).contains(p) else { return startEmptyDrag(at: p, event: event) }
            if event.clickCount == 2 { return beginRename(action, in: row) }

            var selected = Set(controller.selectedActions.map(\.id))
            if extending {
                if selected.contains(action.id) { selected.remove(action.id) } else { selected.insert(action.id) }
                controller.selectActions(selected)
                if selected.isEmpty { controller.deselectActions() }
                guard selected.contains(action.id) else { return }
            } else if !selected.contains(action.id) {
                controller.selectActions([action.id])
            }

            if !action.isInstant, !extending, abs(p.x - rect.minX) <= Self.edgeHit {
                drag = .trim(original: action, startEdge: true, startX: p.x)
                controller.begin("Change Timing")
            } else if !action.isInstant, !extending, abs(p.x - rect.maxX) <= Self.edgeHit {
                drag = .trim(original: action, startEdge: false, startX: p.x)
                controller.begin("Change Timing")
            } else {
                let originals = controller.selectedActions
                drag = .move(originals: originals, anchor: action, startX: p.x)
                controller.begin(originals.count == 1 ? "Move Action" : "Move Actions")
            }
        }
        needsDisplay = true
    }

    /// Empty space: a box to select with, or with Option, a pan.
    private func startEmptyDrag(at p: CGPoint, event: NSEvent) {
        guard let controller, let viewport else { return }
        if event.modifierFlags.contains(.option) {
            drag = .pan(startX: p.x, startTime: viewport.start)
            return
        }
        let extending = event.modifierFlags.contains(.shift) || event.modifierFlags.contains(.command)
        let base = extending ? Set(controller.selectedActions.map(\.id)) : []
        if !extending { controller.deselectActions() }
        drag = .marquee(start: p, current: p, base: base)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let viewport else { return }
        drag = .pan(startX: convert(event.locationInWindow, from: nil).x, startTime: viewport.start)
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    override func mouseDragged(with event: NSEvent) {
        guard let controller, let viewport, let drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        let rate = controller.frameRate
        switch drag {
        case .move(let originals, let anchor, let startX):
            let ids = Set(originals.map(\.id))
            let edges = anchor.isInstant ? [anchor.start] : [anchor.start, anchor.end]
            let delta = snapped((p.x - startX) / viewport.pointsPerSecond, edges: edges, ignoring: ids)
            var edited = Dictionary(uniqueKeysWithValues: ActionEditing.moved(originals, by: delta, rate: rate).map { ($0.id, $0) })
            // One action dragged onto another of its layer's rows moves there.
            if originals.count == 1, let over = row(at: p.y)?.action, over.targetLayerID == anchor.targetLayerID,
               over.id != anchor.id,
               let index = ActionEditing.rows(on: anchor.targetLayerID, in: controller.project).firstIndex(where: { $0.id == over.id }) {
                for changed in ActionEditing.moving(anchor.id, toRow: index, in: controller.project) {
                    if var existing = edited[changed.id] {
                        existing.rowOrder = changed.rowOrder
                        edited[changed.id] = existing
                    } else {
                        edited[changed.id] = changed
                    }
                }
            }
            controller.update(.updateActions(Array(edited.values)))

        case .trim(let original, let startEdge, let startX):
            let edge = startEdge ? original.start : original.end
            let target = edge + snapped((p.x - startX) / viewport.pointsPerSecond, edges: [edge], ignoring: [original.id])
            let trimmed = ActionEditing.trimmed(original, startEdge: startEdge, to: target,
                                                symmetric: event.modifierFlags.contains(.option), rate: rate)
            controller.update(.updateActions([trimmed]))

        case .marquee(let start, _, let base):
            self.drag = .marquee(start: start, current: p, base: base)
            let box = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            var picked = base
            for row in rows {
                if let action = row.action, barRect(action, in: row).intersects(box) { picked.insert(action.id) }
            }
            if picked.isEmpty { controller.deselectActions() } else { controller.selectActions(picked) }

        case .pan(let startX, let startTime):
            viewport.start = startTime - (p.x - startX) / viewport.pointsPerSecond
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        switch drag {
        case .move, .trim: controller?.end()
        case .marquee, .pan: break
        }
        self.drag = nil
        needsDisplay = true
    }

    /// A time difference nudged so one of `edges` lands exactly on the
    /// playhead, the scene's start or end, or another action's start or end,
    /// when it comes within a few points of one.
    private func snapped(_ delta: Double, edges: [Double], ignoring: Set<UUID>) -> Double {
        guard let controller, let viewport else { return delta }
        var targets = [controller.editor.time, controller.duration, 0]
        for a in controller.project.actions where !ignoring.contains(a.id) { targets += [a.start, a.end] }
        var best = delta
        var nearest = Self.snapDistance / viewport.pointsPerSecond
        for edge in edges {
            for target in targets where abs(target - (edge + delta)) < nearest {
                nearest = abs(target - (edge + delta))
                best = target - edge
            }
        }
        return best
    }

    // MARK: Renaming

    private func beginRename(_ action: Action, in row: TimelineRow) {
        let rect = barRect(action, in: row)
        let field = NSTextField(frame: CGRect(x: max(rect.minX, gutter), y: row.y + 2,
                                              width: max(rect.width, 160), height: row.height - 4))
        field.stringValue = action.name
        field.font = NSFont.systemFont(ofSize: 11)
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor(Theme.panelRaised)
        field.textColor = NSColor(Theme.textPrimary)
        field.delegate = self
        addSubview(field)
        renaming = (action.id, field)
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endRename(commit: true)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(cancelOperation(_:)) {
            endRename(commit: false)
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func endRename(commit: Bool) {
        guard let (id, field) = renaming else { return }
        renaming = nil
        let name = field.stringValue
        field.removeFromSuperview()
        if commit { controller?.renameAction(id, to: name) }
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
            // Up and down scroll the rows.
            super.scrollWheel(with: event)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil).x)
    }

    private func zoom(by factor: Double, around x: Double) {
        guard let viewport else { return }
        let t = time(at: x)
        viewport.pointsPerSecond = min(max(viewport.pointsPerSecond * factor, 5), 20_000)
        viewport.start = t - (x - gutter) / viewport.pointsPerSecond
        needsDisplay = true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        let step = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51, 117:                                                // delete, forward delete
            controller.deleteSelection()
        case 53:                                                     // escape
            if drag != nil {
                controller.cancel()
                drag = nil
            } else {
                controller.deselectActions()
            }
            needsDisplay = true
        case 123 where flags.isEmpty: controller.nudgeActions(frames: -step)
        case 124 where flags.isEmpty: controller.nudgeActions(frames: step)
        default:
            if !EditorKeys.handle(event, controller) { super.keyDown(with: event) }
        }
    }
}

extension ActionKind {
    var icon: Icon {
        switch self {
        case .move: return .move
        case .scale: return .scale
        case .rotate: return .rotate
        case .opacity: return .opacity
        case .resize: return .resize
        case .visibility: return .eye
        case .color: return .color
        case .stroke: return .stroke
        case .trim: return .trim
        case .cornerRadius: return .corners
        case .shadow: return .shadow
        case .layerBlur: return .layerBlur
        case .backgroundBlur: return .backgroundBlur
        }
    }
}

/// The bare keys the canvas and the timeline share. None of them are menu
/// keys, so the same letter typed into a field stays a letter.
enum EditorKeys {
    /// M switches between Design and Animate. In Animate, Space plays and
    /// pauses, comma and full stop step a frame (Shift for ten, Option for
    /// the previous or next start or end of an action), and Home and End go
    /// to the ends.
    static func handle(_ event: NSEvent, _ controller: EditorController) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "m" {
            controller.toggleMode()
            return true
        }
        guard controller.editor.mode == .animate else { return false }
        let steps = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 43, 47:                                             // comma, full stop
            guard !flags.contains(.command), !flags.contains(.control) else { return false }
            let forward = event.keyCode == 47
            if flags.contains(.option) { controller.jumpToEdge(forward: forward) } else { controller.step(forward ? steps : -steps) }
            return true
        case 49 where flags.isEmpty: controller.togglePlay(); return true   // space
        case 115 where flags.isEmpty: controller.jumpToStart(); return true // home
        case 119 where flags.isEmpty: controller.jumpToEnd(); return true   // end
        default: return false
        }
    }
}
