import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// The rows under the ruler, in a scroll view of their own so the ruler and
/// the transport stay put while a long list of actions scrolls.
struct ActionTimeline: NSViewRepresentable {
    let controller: EditorController
    let editor: EditorModel

    @Environment(MenuHost.self) private var menus

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        let tracks = TimelineTracksView(frame: .zero)
        tracks.controller = controller
        tracks.menus = menus
        tracks.autoresizingMask = [.width]
        scroll.documentView = tracks
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tracks = scroll.documentView as? TimelineTracksView else { return }
        // Read here so SwiftUI calls this whenever any of them change.
        _ = (editor.time, editor.selection, editor.selectedActions, editor.timelineOnlySelected,
             editor.viewport.pointsPerSecond, editor.viewport.start, controller.project, editor.revealActions.request)
        tracks.menus = menus
        tracks.reload()
    }
}

/// Every action on a row of its own, in the order actions were added: a
/// label naming its layer and itself down the left, and its bar on the
/// right, drawn and handled in AppKit for exact positions.
///
/// Drag a bar to move it in time, or up and down (or drag its label) to
/// reorder. Drag an end to change its length (Option for both ends). Click,
/// Shift- or Command-click, or drag a box to select. The eye that shows on a
/// hovered label switches an action off. Double-click a label to rename its
/// action. Right-click for Stagger and what to show. Option-drag empty
/// space, or scroll sideways, to pan; Command-scroll or pinch to zoom.
final class TimelineTracksView: NSView, NSTextFieldDelegate {
    var controller: EditorController? {
        didSet { controller?.waveforms.onChange = { [weak self] in self?.needsDisplay = true } }
    }
    /// For the right-click menu and the stagger card.
    var menus: MenuHost?
    private(set) var rows: [TimelineRow] = []

    private var drag: Drag?
    private var lastSelection: Set<UUID> = []
    private var lastReveal = 0
    private var renaming: (id: UUID, field: NSTextField)?
    /// The row whose label is under the pointer, which shows its eye and
    /// lights up as the layers panel's rows do.
    private var hoveredLabel: Int?
    /// The bar under the pointer, which shows a handle at each end.
    private var hoveredBar: UUID?

    /// How near, in points, a dragged time jumps to something worth lining up with.
    static let snapDistance = 6.0
    static let edgeHit = 5.0
    /// On a bar long enough to keep a middle to grab, a trim reaches this
    /// far in from each end, so the handle drawn there is all trim.
    static let edgeReach = 10.0
    /// The handles a hovered bar shows at its ends.
    static let handleSize = CGSize(width: 3, height: 12)
    static let handleInset = 4.0
    static let instantWidth = 12.0
    /// The eye's square at the right of a label.
    static let eyeBox = 22.0

    private enum Drag {
        case move(originals: [Action], anchor: Action, startX: Double)
        case trim(original: Action, startEdge: Bool, startX: Double)
        case reorder(action: Action, began: Bool)
        case marquee(start: CGPoint, current: CGPoint, base: Set<UUID>)
        case pan(startX: Double, startTime: Double)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var viewport: TimelineViewport? { controller?.editor.viewport }
    private let gutter = TimelineRow.labelWidth

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
        if editor.revealActions.request != lastReveal {
            lastReveal = editor.revealActions.request
            reveal(editor.revealActions.ids)
        }
        needsDisplay = true
    }

    /// Scrolls, gently, just far enough to bring these actions' rows into
    /// view: a row added below the fold slides up into sight.
    private func reveal(_ ids: Set<UUID>) {
        let mine = rows.filter { ids.contains($0.action.id) }
        guard let first = mine.first, let last = mine.last, let scroll = enclosingScrollView else { return }
        let clip = scroll.contentView
        let visible = clip.bounds
        let top = first.y, bottom = last.y + TimelineRow.height
        var y = visible.minY
        if bottom > visible.maxY { y = bottom - visible.height }
        if top < y { y = top }
        y = min(max(y, 0), max(bounds.height - visible.height, 0))
        guard abs(y - visible.minY) > 0.5 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clip.animator().setBoundsOrigin(NSPoint(x: visible.minX, y: y))
        } completionHandler: {
            MainActor.assumeIsolated { scroll.reflectScrolledClipView(clip) }
        }
    }

    private func sizeToRows() {
        guard let clip = enclosingScrollView?.contentView else { return }
        let height = max(CGFloat(rows.count) * TimelineRow.height, clip.bounds.height)
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
        scrollToVisible(CGRect(x: 0, y: first.y, width: 1, height: last.y + TimelineRow.height - first.y))
    }

    private func rowIndex(at y: CGFloat) -> Int? {
        let i = Int((y / TimelineRow.height).rounded(.down))
        return i >= 0 && i < rows.count ? i : nil
    }

    private func barRect(_ action: Action, in row: TimelineRow) -> CGRect {
        let x0 = x(for: action.start)
        let h = TimelineRow.barHeight, top = row.y + (TimelineRow.height - h) / 2
        if action.isInstant {
            return CGRect(x: x0 - Self.instantWidth / 2, y: row.y + (TimelineRow.height - Self.instantWidth) / 2,
                          width: Self.instantWidth, height: Self.instantWidth)
        }
        return CGRect(x: x0, y: top, width: max(x(for: action.end) - x0, 4), height: h)
    }

    /// How far in from each end a press trims rather than moves.
    private func trimReach(_ rect: CGRect) -> Double { rect.width >= Self.edgeReach * 3.6 ? Self.edgeReach : Self.edgeHit }

    /// Which end of a bar a point would trim, if any.
    private func trimEdge(at p: CGPoint, of action: Action, rect: CGRect) -> Bool? {
        guard !action.isInstant, p.x >= rect.minX - Self.edgeHit, p.x <= rect.maxX + Self.edgeHit else { return nil }
        let reach = trimReach(rect)
        if p.x <= rect.minX + reach { return true }
        if p.x >= rect.maxX - reach { return false }
        return nil
    }

    private func eyeRect(_ row: TimelineRow) -> CGRect {
        CGRect(x: gutter - Self.eyeBox - 8, y: row.y + (TimelineRow.height - Self.eyeBox) / 2,
               width: Self.eyeBox, height: Self.eyeBox)
    }

    override func layout() {
        super.layout()
        fitIfNeeded()
    }

    /// The whole composition across the tracks at first sight.
    private func fitIfNeeded() {
        guard let viewport, let controller, !viewport.hasFitted, bounds.width - gutter > 40 else { return }
        viewport.pointsPerSecond = max((bounds.width - gutter - TimelineViewport.lead * 2) / max(controller.duration, 0.1), 1)
        viewport.start = -TimelineViewport.lead / viewport.pointsPerSecond
        viewport.hasFitted = true
    }

    /// The app's arrow over the whole timeline, so AppKit never falls back
    /// to the system's between moves.
    override func resetCursorRects() {
        addCursorRect(visibleRect, cursor: Cursors.arrow)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let index = rowIndex(at: p.y)
        let label = p.x < gutter ? index : nil
        var bar: UUID?
        var trims = false
        if let index, p.x >= gutter {
            let row = rows[index]
            let rect = barRect(row.action, in: row)
            if rect.insetBy(dx: -Self.edgeHit, dy: 0).contains(p) {
                bar = row.action.id
                trims = trimEdge(at: p, of: row.action, rect: rect) != nil
            }
        }
        if drag == nil { (trims ? Cursors.resizeHorizontal : Cursors.arrow).set() }
        if label != hoveredLabel || bar != hoveredBar {
            hoveredLabel = label
            hoveredBar = bar
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        Cursors.arrow.set()
        hoveredLabel = nil
        hoveredBar = nil
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let ctx = NSGraphicsContext.current?.cgContext else { return }
        let selectedLayers = controller.editor.selection
        let selectedActions = Set(controller.selectedActions.map(\.id))

        for (index, row) in rows.enumerated() where row.y + TimelineRow.height >= dirtyRect.minY && row.y <= dirtyRect.maxY {
            drawRow(row, index: index, layerSelected: selectedLayers.contains(row.layerID),
                    selected: selectedActions.contains(row.action.id), in: ctx)
        }

        // After the composition ends, dimmed.
        let endX = x(for: controller.duration)
        if endX < bounds.width {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.22))
            ctx.fill(CGRect(x: max(endX, gutter), y: 0, width: bounds.width - max(endX, gutter), height: bounds.height))
        }
        // The line between the labels and the bars.
        ctx.setFillColor(NSColor(Theme.border).cgColor)
        ctx.fill(CGRect(x: gutter - 1, y: 0, width: 1, height: bounds.height))

        let px = x(for: controller.editor.time).rounded() + 0.5
        if px >= gutter {
            ctx.setFillColor(NSColor(Theme.playhead).cgColor)
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

    private func drawRow(_ row: TimelineRow, index: Int, layerSelected: Bool, selected: Bool, in ctx: CGContext) {
        let action = row.action
        let full = CGRect(x: 0, y: row.y, width: bounds.width, height: TimelineRow.height)
        let label = CGRect(x: 0, y: row.y, width: gutter, height: TimelineRow.height)

        // The row: the accent across it when its action is selected, a tint
        // when only its layer is.
        if selected {
            ctx.setFillColor(NSColor(Theme.accent).withAlphaComponent(0.35).cgColor)
            ctx.fill(full)
            ctx.setFillColor(NSColor(Theme.accent).cgColor)
            ctx.fill(label)
        } else if layerSelected {
            ctx.setFillColor(NSColor(Theme.rowHover).cgColor)
            ctx.fill(full)
        }
        // Under the pointer, the label lights up as a layers panel row does.
        if hoveredLabel == index, !selected {
            ctx.setFillColor(NSColor(Theme.rowHover).cgColor)
            ctx.fill(label)
        }
        // The faint line under every row.
        ctx.setFillColor(NSColor(Theme.border).withAlphaComponent(0.45).cgColor)
        ctx.fill(CGRect(x: 0, y: row.y + TimelineRow.height - 1, width: bounds.width, height: 1))

        // The label: layer, then action.
        let dimmed = !action.isEnabled
        let primary = NSColor(selected ? Theme.textPrimary : dimmed ? Theme.textTertiary : Theme.textPrimary)
        let secondary = NSColor(selected ? Theme.textPrimary : Theme.textTertiary).withAlphaComponent(selected ? 0.75 : 1)
        // Only under the pointer: an action switched off already shows as
        // much in its dimmed label and bar.
        let showsEye = hoveredLabel == index
        let room = gutter - 16 - (showsEye ? Self.eyeBox + 12 : 12)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: 16, y: row.y, width: max(room, 0), height: TimelineRow.height))
        let layerAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .medium),
                                                              .foregroundColor: primary]
        let actionAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: secondary]
        let layerName = row.layerName as NSString
        let textY = row.y + (TimelineRow.height - 15) / 2
        layerName.draw(at: CGPoint(x: 16, y: textY), withAttributes: layerAttributes)
        var cursor = 16 + layerName.size(withAttributes: layerAttributes).width + 7
        ctx.setFillColor(secondary.cgColor)
        ctx.fillEllipse(in: CGRect(x: cursor, y: row.y + TimelineRow.height / 2 - 1.5, width: 3, height: 3))
        cursor += 10
        (action.name as NSString).draw(at: CGPoint(x: cursor, y: textY), withAttributes: actionAttributes)
        ctx.restoreGState()
        if showsEye {
            let eye = eyeRect(row).insetBy(dx: 4, dy: 4)
            drawIcon(action.isEnabled ? .eye : .eyeSlash, in: eye,
                     color: NSColor(selected ? Theme.textPrimary : Theme.textSecondary), in: ctx)
        }

        // The bar.
        let rect = barRect(action, in: row)
        ctx.saveGState()
        ctx.clip(to: CGRect(x: gutter, y: row.y, width: bounds.width - gutter, height: TimelineRow.height))
        ctx.setAlpha(dimmed ? 0.4 : 1)
        let radius = action.isInstant ? 3 : 6.0
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.setFillColor(NSColor(selected ? Theme.accent : Theme.panelHover).cgColor)
        ctx.fillPath()
        if case .play(let play) = action.spec { drawWaveform(action, play: play, in: rect, selected: selected, ctx: ctx) }
        // Under the pointer, a handle at each end says the ends drag.
        if hoveredBar == action.id, !action.isInstant, rect.width >= Self.edgeReach * 2.4 {
            let size = Self.handleSize
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            for x in [rect.minX + Self.handleInset, rect.maxX - Self.handleInset - size.width] {
                let handle = CGRect(x: x, y: rect.midY - size.height / 2, width: size.width, height: size.height)
                ctx.addPath(CGPath(roundedRect: handle, cornerWidth: size.width / 2, cornerHeight: size.width / 2, transform: nil))
            }
            ctx.fillPath()
        }
        ctx.restoreGState()
    }

    /// A sound's loudness along its Play bar, for the part of the file it
    /// plays, drawn faintly inside it. Volume actions shape it, so a fade
    /// shows as the waveform tapering, against the loudest the layer gets.
    private func drawWaveform(_ action: Action, play: PlayAction, in rect: CGRect, selected: Bool, ctx: CGContext) {
        guard let controller, let asset = controller.asset(ofLayer: action.targetLayerID), asset.hasAudio,
              let peaks = controller.waveforms.peaks(for: asset.id, at: controller.document?.mediaURL(for: asset.id)),
              !peaks.isEmpty, action.duration > 0 else { return }
        var level: ((Double) -> Double)?
        let fades = controller.project.actions(on: action.targetLayerID).filter { $0.isEnabled && $0.spec.kind == .volume }
        if !fades.isEmpty, let layer = controller.project.layer(withID: action.targetLayerID) {
            let envelope = volumeEnvelope(of: layer, fades)
            let design = LayerState(design: layer).volume ?? 1
            let loudest = max(envelope.map(\.volume).max() ?? 0, design, 1e-6)
            let curve = AudioClip(mediaID: asset.id, start: 0, sourceStart: 0, duration: 0, volume: design, envelope: envelope)
            level = { time in min(max(curve.volume(at: time) / loudest, 0), 1) }
        }
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1, dy: 2), cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.clip()
        let visible = rect.intersection(CGRect(x: gutter, y: rect.minY, width: bounds.width - gutter, height: rect.height))
        let path = CGMutablePath()
        let mid = rect.midY, half = rect.height / 2 - 3
        var x = visible.minX.rounded(.down)
        while x <= visible.maxX {
            let t = play.trimStart + Double(x - rect.minX) / rect.width * action.duration
            let i = Int(t * Waveforms.peaksPerSecond)
            if i >= 0, i < peaks.count {
                let scale = level.map { CGFloat($0(action.start + (t - play.trimStart))) } ?? 1
                let h = max(CGFloat(peaks[i]) * half * scale, 0.5)
                path.addRect(CGRect(x: x, y: mid - h, width: 1, height: h * 2))
            }
            x += 2
        }
        ctx.addPath(path)
        ctx.setFillColor(NSColor(Theme.textPrimary).withAlphaComponent(selected ? 0.45 : 0.22).cgColor)
        ctx.fillPath()
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

        guard let index = rowIndex(at: p.y) else { return startEmptyDrag(at: p, event: event) }
        let row = rows[index]
        let action = row.action

        // The label: the eye switches the action off; a double-click
        // renames it; a drag reorders.
        if p.x < gutter {
            if eyeRect(row).contains(p), hoveredLabel == index { return controller.toggleEnabled(action) }
            if event.clickCount == 2 { return beginRename(row) }
            pick(action, extending: extending)
            if !extending { drag = .reorder(action: action, began: false) }
            needsDisplay = true
            return
        }

        let rect = barRect(action, in: row)
        guard rect.insetBy(dx: -Self.edgeHit, dy: 0).contains(p) else { return startEmptyDrag(at: p, event: event) }
        if event.clickCount == 2 { return beginRename(row) }
        guard pick(action, extending: extending) else { return }

        if !extending, let startEdge = trimEdge(at: p, of: action, rect: rect) {
            drag = .trim(original: action, startEdge: startEdge, startX: p.x)
            controller.begin("Change Timing")
        } else {
            let originals = controller.selectedActions
            drag = .move(originals: originals, anchor: action, startX: p.x)
            controller.begin(originals.count == 1 ? "Move Action" : "Move Actions")
        }
        needsDisplay = true
    }

    /// Selects an action as a click does: on its own, or with Shift or
    /// Command, added or taken away. Returns whether it ends up selected.
    @discardableResult
    private func pick(_ action: Action, extending: Bool) -> Bool {
        guard let controller else { return false }
        var selected = Set(controller.selectedActions.map(\.id))
        if extending {
            if selected.contains(action.id) { selected.remove(action.id) } else { selected.insert(action.id) }
            if selected.isEmpty { controller.deselectActions() } else { controller.selectActions(selected) }
            return selected.contains(action.id)
        }
        if !selected.contains(action.id) { controller.selectActions([action.id]) }
        return true
    }

    /// Empty space: a box to select with, or with Option, a pan.
    private func startEmptyDrag(at p: CGPoint, event: NSEvent) {
        guard let controller, let viewport else { return }
        if event.modifierFlags.contains(.option) {
            drag = .pan(startX: p.x, startTime: viewport.start)
            Cursors.handGrabbed.set()
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
        Cursors.handGrabbed.set()
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func otherMouseUp(with event: NSEvent) { mouseUp(with: event) }

    /// The actions whose row changes when `action` moves to the row under
    /// `y`, against the project as it is now. Empty when it is on that row
    /// already. A drag's steps each build on the last, so each sends every
    /// row that differs from now.
    private func reordered(_ action: Action, toRowAt y: CGFloat) -> [Action] {
        guard let controller else { return [] }
        // The rows as they are this moment, not as last drawn: a quick drag
        // can outrun the drawing.
        let editor = controller.editor
        let current = TimelineRow.rows(of: controller.project, only: editor.timelineOnlySelected ? editor.selection : nil)
        let index = min(max(Int((y / TimelineRow.height).rounded(.down)), 0), current.count - 1)
        guard index >= 0, current[index].action.id != action.id,
              let target = ActionEditing.timeline(in: controller.project).firstIndex(where: { $0.id == current[index].action.id })
        else { return [] }
        return ActionEditing.moving(action.id, toRow: target, in: controller.project)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller, let viewport, let drag else { return }
        let p = convert(event.locationInWindow, from: nil)
        let rate = controller.frameRate
        switch drag {
        case .move(let originals, let anchor, let startX):
            let ids = Set(originals.map(\.id))
            let edges = anchor.isInstant ? [anchor.start] : [anchor.start, anchor.end]
            let delta = snapped((p.x - startX) / viewport.pointsPerSecond, edges: edges, ignoring: ids)
            // Times from where the drag began; rows as they are now.
            let rowsNow = Dictionary(controller.project.actions.map { ($0.id, $0.rowOrder) }, uniquingKeysWith: { a, _ in a })
            var edited = Dictionary(uniqueKeysWithValues: ActionEditing.moved(originals, by: delta, rate: rate).map { moved -> (UUID, Action) in
                var a = moved
                a.rowOrder = rowsNow[a.id] ?? a.rowOrder
                return (a.id, a)
            })
            // One action dragged onto another row moves there.
            if originals.count == 1 {
                for changed in reordered(anchor, toRowAt: p.y) {
                    if var existing = edited[changed.id] {
                        existing.rowOrder = changed.rowOrder
                        edited[changed.id] = existing
                    } else {
                        edited[changed.id] = changed
                    }
                }
            }
            controller.update(.updateActions(Array(edited.values)))

        case .reorder(let action, let began):
            let changed = reordered(action, toRowAt: p.y)
            guard !changed.isEmpty else { break }
            if !began {
                controller.begin("Reorder")
                self.drag = .reorder(action: action, began: true)
            }
            controller.update(.updateActions(changed))

        case .trim(let original, let startEdge, let startX):
            let edge = startEdge ? original.start : original.end
            let target = edge + snapped((p.x - startX) / viewport.pointsPerSecond, edges: [edge], ignoring: [original.id])
            let trimmed = ActionEditing.trimmed(original, startEdge: startEdge, to: target,
                                                symmetric: event.modifierFlags.contains(.option), rate: rate,
                                                mediaLength: controller.asset(ofLayer: original.targetLayerID)?.duration)
            controller.update(.updateActions([trimmed]))

        case .marquee(let start, _, let base):
            self.drag = .marquee(start: start, current: p, base: base)
            let box = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            var picked = base
            for row in rows where barRect(row.action, in: row).intersects(box) { picked.insert(row.action.id) }
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
        case .reorder(_, let began): if began { controller?.end() }
        case .marquee(let start, let current, _):
            // A click rather than a box: the playhead goes there.
            if let controller, start.x >= gutter, hypot(current.x - start.x, current.y - start.y) < 3 {
                controller.stop()
                controller.glide(to: max(time(at: start.x), 0))
            }
        case .pan:
            Cursors.arrow.set()
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

    // MARK: Right-click

    override func rightMouseDown(with event: NSEvent) {
        guard let controller, let menus, let window, let content = window.contentView else { return }
        let p = convert(event.locationInWindow, from: nil)
        // A right-click on an unselected row picks it first, as Finder does.
        if let index = rowIndex(at: p.y), !controller.selectedActions.contains(where: { $0.id == rows[index].action.id }) {
            controller.selectActions([rows[index].action.id])
        }
        let inWindow = convert(p, to: nil)
        let origin = CGPoint(x: inWindow.x, y: content.bounds.height - inWindow.y)
        let editor = controller.editor
        menus.show([
            .item("Stagger…", disabled: controller.selectedActions.count < 2) {
                menus.showPopup(at: origin) { StaggerCard(controller: controller) { menus.dismiss() } }
            },
            .separator,
            .item("Show Only Selected Layers", checked: editor.timelineOnlySelected) { editor.timelineOnlySelected.toggle() },
            .item("Show Times as Frames", checked: editor.showsFrames) { editor.showsFrames.toggle() },
        ], at: origin)
    }

    // MARK: Renaming

    private func beginRename(_ row: TimelineRow) {
        let field = NSTextField(frame: CGRect(x: 12, y: row.y + 5, width: gutter - 24, height: TimelineRow.height - 10))
        field.stringValue = row.action.name
        field.font = NSFont.systemFont(ofSize: 12)
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = NSColor(Theme.panelRaised)
        field.textColor = NSColor(Theme.textPrimary)
        field.delegate = self
        addSubview(field)
        renaming = (row.action.id, field)
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
        viewport.start = t - (max(x, gutter) - gutter) / viewport.pointsPerSecond
        needsDisplay = true
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        if ExportKeys.handle(event, controller) { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        let step = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 51 where flags.contains(.command):                      // ⌘⌫ ungroups groups and frames
            controller.ungroupSelection()
        case 51, 117:                                                // delete, forward delete
            controller.deleteSelection()
        case 53:                                                     // escape
            if controller.editor.showShortcuts {
                controller.editor.showShortcuts = false
            } else if drag != nil {
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
        case .letterSpacing: return .letterSpacing
        case .lineHeight: return .lineHeight
        case .counter: return .counter
        case .changeText: return .changeText
        case .arc: return .arc
        case .star: return .star
        case .path: return .pen
        case .play: return .play
        case .volume: return .speaker
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
