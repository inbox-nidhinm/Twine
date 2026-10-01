import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation

// Test driver for the separate test copy of the app. Installed into the app
// by Tools/SelfTest/install-hook.sh and taken out again by remove-hook.sh;
// never committed inside Twine/. Runs a script of clicks,
// keys and seeks in one window, and pauses at each "shot" until the
// screenshot it asked for exists.
nonisolated func log(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

/// Keys held and clicks counted for the step being run.
final class Held {
    var flags: NSEvent.ModifierFlags = []
    var clicks = 1
}

enum SelfTest {
    /// The script runs once, from the first project to open; later ones (a
    /// second project, or one reopened from home) only show in the log.
    nonisolated(unsafe) static var started = false

    static func run(window: NSWindow, controller: EditorController, menus: MenuHost) {
        guard !started, let script = ProcessInfo.processInfo.environment["TWINE_SELFTEST"],
              let shots = ProcessInfo.processInfo.environment["TWINE_SHOTS"] else { return }
        started = true
        let steps = script.split(separator: ";").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let held = Held()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { step(0) }

        func state() -> String {
            let e = controller.editor
            _ = e
            let fr = window.firstResponder.map { String(describing: type(of: $0)) } ?? "-"
            let p0 = controller.selectedLayers.first.map { String(format: "pos=%.1f,%.1f size=%.1f,%.1f", $0.transform.position.x, $0.transform.position.y, $0.size.width, $0.size.height) } ?? "pos=-"
            let shown = MainWindow.window.windowController.map { String(describing: type(of: $0)).replacingOccurrences(of: "WindowController", with: "") } ?? "-"
            let wins = NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) }.count
            let docs = NSDocumentController.shared.documents.map { $0.displayName ?? "?" }
            return "window=\(shown) wins=\(wins) docs=\(docs) " + "hov=\(controller.editor.hoveredLayer.flatMap { controller.project.layer(withID: $0)?.name } ?? "-") " + p0 + " vstart=\(String(format: "%.3f", e.viewport.start)) pps=\(Int(e.viewport.pointsPerSecond)) layers=\(controller.project.allLayers.count) actions=\(controller.project.actions.map(\.name)) sel=\(controller.selectedLayers.map { "\($0.name)@\(Int($0.transform.position.x)),\(Int($0.transform.position.y))" }) mode=\(e.mode) tool=\(e.tool) time=\(String(format: "%.3f", e.time)) playing=\(e.isPlaying) export=\(e.exports.progress.map { String(format: "%.2f", $0) } ?? "-")/\(e.exports.finished?.lastPathComponent ?? "-") sheet=\(window.attachedSheet != nil) menu=\(menus.isOpen) onb=\(OnboardingState.shared.isShowing ? "\(OnboardingState.shared.page)/\(OnboardingState.shared.feature.rawValue)" : "-") fr=\(fr.prefix(40))"
        }
        func mouse(_ type: NSEvent.EventType, _ x: Double, _ y: Double) {
            let p = NSPoint(x: x, y: window.contentView!.bounds.height - y)
            let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: held.flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: held.clicks, pressure: 1)!
            window.sendEvent(e)
        }
        func key(_ chars: String, _ code: UInt16) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: held.flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: chars,
                                         charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
                window.sendEvent(e)
            }
        }
        func tick() {
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: false)
            }
        }
        func shot(_ name: String, then next: @escaping () -> Void) {
            let path = shots + "/" + name + ".png"
            log("SHOT \(name)")
            func poll(_ n: Int) {
                if FileManager.default.fileExists(atPath: path) || n > 100 { next(); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { poll(n + 1) }
            }
            poll(0)
        }
        func step(_ i: Int) {
            guard i < steps.count else { log("done " + state()); return }
            var parts = steps[i].split(separator: " ").map(String.init)
            // A prefix of held keys: "opt+drag ...", "shift+click ...", "cmd+key ...", "dbl+click ...".
            held.flags = []
            held.clicks = 1
            if let plus = parts[0].firstIndex(of: "+") {
                for m in parts[0][..<plus].split(separator: ",") {
                    switch m {
                    case "opt": held.flags.insert(.option)
                    case "shift": held.flags.insert(.shift)
                    case "cmd": held.flags.insert(.command)
                    case "ctrl": held.flags.insert(.control)
                    case "dbl": held.clicks = 2
                    default: break
                    }
                }
                parts[0] = String(parts[0][parts[0].index(after: plus)...])
            }
            let n = parts.dropFirst().compactMap(Double.init)
            var wait = 0.5
            func next() {
                tick()
                DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
                    log("after \(steps[i]): " + state())
                    step(i + 1)
                }
            }
            switch parts[0] {
            case "shot": wait = 0.05; shot(parts[1], then: next); return
            case "open", "pick":
                let wantOpen = parts[0] == "open"
                func attempt(_ k: Int) {
                    mouse(.leftMouseDown, n[0], n[1]); mouse(.leftMouseUp, n[0], n[1])
                    tick()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        if menus.isOpen != wantOpen && k < 4 { log("retry \(steps[i])"); attempt(k + 1) } else { next() }
                    }
                }
                attempt(0); return
            case "key":
                switch parts[1] {
                case "space": key(" ", 49)
                case "enter": key("\r", 36)
                case "del": key("\u{7f}", 51)
                case "left": key("\u{f702}", 123)
                case "right": key("\u{f703}", 124)
                case "up": key("\u{f700}", 126)
                case "down": key("\u{f701}", 125)
                case "comma": key(",", 43)
                case "stop": key(".", 47)
                case "esc": key("\u{1b}", 53)
                default: key(parts[1], 0)
                }
            case "type": for c in parts[1] { key(String(c), 0) }
            case "clear": for _ in 0..<14 { key("\u{7f}", 51); key("\u{f728}", 117) }
            case "click": mouse(.leftMouseDown, n[0], n[1]); mouse(.leftMouseUp, n[0], n[1])
            case "scroll":
                // The scroll view under the point, moved by DY points down
                // its content, as a wheel would.
                var v = (window as? ChromelessWindow)?.viewUnder(NSPoint(x: n[0], y: window.contentView!.bounds.height - n[1]))
                while let view = v, !(view is NSScrollView) { v = view.superview }
                if let scroll = v as? NSScrollView {
                    let clip = scroll.contentView
                    var origin = clip.bounds.origin
                    origin.y += clip.isFlipped ? n[2] : -n[2]
                    clip.scroll(to: origin)
                    scroll.reflectScrolledClipView(clip)
                    log("SCROLL to \(Int(origin.y))")
                } else {
                    log("SCROLL no scroll view")
                }
            case "rclick": mouse(.rightMouseDown, n[0], n[1]); mouse(.rightMouseUp, n[0], n[1])
            case "qrclick", "qclick":
                // Through the app's event queue, as a real click comes, so
                // views that look at the current event (right-click menus
                // over SwiftUI) see it for what it is.
                let p = NSPoint(x: n[0], y: window.contentView!.bounds.height - n[1])
                let (down, up): (NSEvent.EventType, NSEvent.EventType) = parts[0] == "qrclick" ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
                for type in [down, up] {
                    if let e = NSEvent.mouseEvent(with: type, location: p, modifierFlags: held.flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: held.clicks, pressure: 1) {
                        NSApp.postEvent(e, atStart: false)
                    }
                }
            case "drag":
                mouse(.leftMouseDown, n[0], n[1])
                for k in 1...10 {
                    let t = Double(k) / 10
                    mouse(.leftMouseDragged, n[0] + (n[2] - n[0]) * t, n[1] + (n[3] - n[1]) * t)
                }
                mouse(.leftMouseUp, n[2], n[3])
            case "hover":
                let p = NSPoint(x: n[0], y: window.contentView!.bounds.height - n[1])
                let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
                func find(_ v: NSView) -> NSView? {
                    if v is TimelineTracksView { return v }
                    for sub in v.subviews { if let f = find(sub) { return f } }
                    return nil
                }
                if let v = find(window.contentView!) { v.mouseMoved(with: e) }
            case "rhover":
                let p = NSPoint(x: n[0], y: window.contentView!.bounds.height - n[1])
                let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
                func findRuler(_ v: NSView) -> NSView? {
                    if v is TimelineRulerView { return v }
                    for sub in v.subviews { if let f = findRuler(sub) { return f } }
                    return nil
                }
                findRuler(window.contentView!)?.mouseMoved(with: e)
            case "chover":
                let p = NSPoint(x: n[0], y: window.contentView!.bounds.height - n[1])
                let e = NSEvent.mouseEvent(with: .mouseMoved, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
                func findCanvas(_ v: NSView) -> NSView? {
                    if v is CanvasNSView { return v }
                    for sub in v.subviews { if let f = findCanvas(sub) { return f } }
                    return nil
                }
                if let v = findCanvas(window.contentView!) { v.mouseMoved(with: e) }
                if let content = window.contentView, let top = content.hitTest(content.convert(p, from: nil)) {
                    var v: NSView? = top; var chain: [String] = []
                    while let cur = v { chain.append(String(describing: type(of: cur)).prefix(40).description); v = cur.superview }
                    log("HIT \(chain.prefix(4))")
                }
                log("HOVER \(controller.editor.hoveredLayer.flatMap { controller.project.layer(withID: $0)?.name } ?? "-")")
            case "clicksample":
                mouse(.leftMouseDown, n[0], n[1]); mouse(.leftMouseUp, n[0], n[1])
                for k in 0..<8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.04) {
                        log("SAMPLE \(k * 40)ms time=\(String(format: "%.3f", controller.editor.time))")
                    }
                }
            case "add":
                // Adds an action of a kind, by name, as the Add Action menu does.
                if let kind = ActionKind(rawValue: parts[1]) { controller.addAction(kind) } else { log("unknown kind \(parts[1])") }
            case "warp":
                // Sets the selected layer's skew and tilt, as the Layer fields do: warp SX SY TX TY.
                let v = parts.dropFirst().compactMap(Double.init)
                if v.count == 4, let id = controller.selection.first {
                    controller.edit(id) { l in
                        l.transform.skew = Vec2(v[0], v[1])
                        l.transform.tilt = Tilt(x: v[2], y: v[3], depth: l.transform.tilt.depth)
                    }
                } else { log("warp needs four numbers and a selection") }
            case "preset":
                // Adds a preset by its id (`slide-in`, `text-letters-rise`...), as the picker does.
                if let preset = Presets.library.first(where: { $0.id == parts[1] }) {
                    controller.addPreset(preset)
                } else if let kind = PresetKind(rawValue: parts[1]) {
                    controller.addPreset(Presets.preset(kind))
                } else {
                    log("unknown preset \(parts[1])")
                }
            case "split":
                // Split into Actions, from the timeline's right-click menu.
                controller.splitSelectedPresets()
            case "sample":
                // The selected layers' position and opacity at a time, as the canvas shows them.
                let t = Double(parts[1]) ?? 0
                let tracks = ActionTracks(controller.project.actions)
                log("SAMPLE t=\(parts[1]) " + controller.selectedLayers.map { l in
                    let st = tracks.state(of: l, at: t)
                    return "\(l.name)@\(Int(st.position.x.rounded())),\(Int(st.position.y.rounded())) o=\(String(format: "%.2f", st.opacity))"
                }.joined(separator: " "))
            case "offers":
                // What Add Action and Add Preset offer for the selection.
                log("OFFERS actions=\(controller.availableActions.map(\.rawValue)) presets=\(controller.availablePresets.map(\.name))")
            case "addsample":
                controller.addAction(parts[1] == "rotate" ? .rotate : .move)
                for k in 0..<8 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(k) * 0.1) {
                        log("SAMPLE \(k * 100)ms time=\(String(format: "%.3f", controller.editor.time))")
                    }
                }
            case "scrollpos":
                func findT(_ v: NSView) -> NSView? {
                    if v is TimelineTracksView { return v }
                    for sub in v.subviews { if let f = findT(sub) { return f } }
                    return nil
                }
                if let t = findT(window.contentView!), let clip = t.enclosingScrollView?.contentView {
                    log("SCROLL y=\(clip.bounds.origin.y) visible=\(clip.bounds.height) doc=\(t.bounds.height)")
                }
            case "arrowcheck":
                NSCursor.arrow.set()
                log("ARROW swapped=\(NSCursor.arrow === Cursors.arrow) current=\(NSCursor.current === Cursors.arrow) size=\(NSCursor.arrow.image.size) hot=\(NSCursor.arrow.hotSpot) iBeamIntact=\(NSCursor.iBeam !== Cursors.arrow)")
            case "swiftuicursor":
                Cursors.hand.set()
                let p = NSPoint(x: n[0], y: window.contentView!.bounds.height - n[1])
                if let e = NSEvent.enterExitEvent(with: .cursorUpdate, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil),
                   let hit = window.contentView?.hitTest(window.contentView!.convert(p, from: nil)) {
                    var v: NSView? = hit
                    var chain: [String] = []
                    while let cur = v { chain.append(String(describing: type(of: cur)).prefix(30).description); v = cur.superview }
                    hit.cursorUpdate(with: e)
                    window.contentView?.cursorUpdate(with: e)
                    log("SWIFTUI current=\(NSCursor.current === Cursors.arrow ? "app arrow" : NSCursor.current === Cursors.hand ? "unchanged" : "other") hit=\(chain.prefix(3))")
                }
            case "scanguard":
                let content = window.contentView!
                let h = content.bounds.height
                log("SCAN content=\(content.frame) flipped=\(content.isFlipped) super=\(String(describing: content.superview.map { type(of: $0) }))")
                var rowsOut: [String] = []
                for y in stride(from: 40.0, to: h - 20, by: 40) {
                    var line = String(format: "%4.0f ", y)
                    for x in stride(from: 260.0, to: 1190, by: 40) {
                        let loc = NSPoint(x: x, y: h - y)
                        let wrong = content.hitTest(content.convert(loc, from: nil))
                        let right = content.superview?.hitTest(loc)
                        func tag(_ v: NSView?) -> String {
                            guard let v else { return "_" }
                            var cur: NSView? = v
                            while let c = cur { if c is CanvasNSView { return "C" }; cur = c.superview }
                            return "x"
                        }
                        line += tag(wrong) + tag(right) + " "
                    }
                    rowsOut.append(line)
                }
                for r in rowsOut { log("SCAN " + r) }
            case "menukey":
                let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: parts[1], charactersIgnoringModifiers: parts[1],
                                         isARepeat: false, keyCode: 44)!
                let handled = NSApp.mainMenu?.performKeyEquivalent(with: e) ?? false
                log("MENUKEY handled=\(handled) shortcuts=\(controller.editor.showShortcuts)")
            case "perfplay":
                // Plays for n[0] seconds and reports how often the playhead
                // actually moved (frames shown) and the longest gap.
                controller.editor.time = 0
                controller.togglePlay()
                var stamps: [CFTimeInterval] = []
                var last = controller.editor.time
                let began = CACurrentMediaTime()
                func tick() {
                    if controller.editor.time != last { stamps.append(CACurrentMediaTime()); last = controller.editor.time }
                    if CACurrentMediaTime() - began < n[0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { tick() }
                    } else {
                        controller.stop()
                        let gaps = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }.sorted()
                        let fps = Double(stamps.count) / n[0]
                        let p95 = gaps.isEmpty ? 0 : gaps[Int(Double(gaps.count) * 0.95)]
                        log(String(format: "PERF play fps=%.1f median=%.1fms p95=%.1fms worst=%.1fms", fps,
                                   gaps.isEmpty ? 0 : gaps[gaps.count / 2], p95, gaps.last ?? 0))
                        next()
                    }
                }
                tick(); return
            case "perfpreview":
                // Plays the export panel's preview for n[0] seconds and reports
                // how often its picture moved on.
                guard let player = controller.editor.exportPlayer else { log("PERF preview: no panel"); break }
                player.seek(0)
                player.play()
                var stamps: [CFTimeInterval] = []
                var last = player.shownTime
                let began = CACurrentMediaTime()
                func sample() {
                    if player.shownTime != last { stamps.append(CACurrentMediaTime()); last = player.shownTime }
                    if CACurrentMediaTime() - began < n[0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { sample() }
                    } else {
                        player.pause()
                        let gaps = zip(stamps.dropFirst(), stamps).map { ($0 - $1) * 1000 }.sorted()
                        log(String(format: "PERF preview fps=%.1f median=%.1fms worst=%.1fms", Double(stamps.count) / n[0],
                                   gaps.isEmpty ? 0 : gaps[gaps.count / 2], gaps.last ?? 0))
                        next()
                    }
                }
                sample(); return
            case "perfscrub":
                // Seeks through n[0] frames as fast as they draw, like a quick scrub.
                let began = CACurrentMediaTime()
                var k = 0
                func step() {
                    guard k < Int(n[0]) else {
                        let each = (CACurrentMediaTime() - began) / n[0] * 1000
                        log(String(format: "PERF scrub %.1f ms per seek", each))
                        next(); return
                    }
                    controller.seek(to: Double(k) / 60)
                    k += 1
                    DispatchQueue.main.async { step() }
                }
                step(); return
            case "perfdrag":
                // Drags the first top-level shape across the canvas in n[0]
                // steps, one per turn of the run loop, and reports the time
                // each step takes to reach the screen.
                func findCanvas(_ v: NSView) -> CanvasNSView? {
                    if let c = v as? CanvasNSView { return c }
                    for sub in v.subviews { if let f = findCanvas(sub) { return f } }
                    return nil
                }
                guard let canvas = findCanvas(window.contentView!), let scene = canvas.scene,
                      let target = scene.layers.first(where: { if case .shape = $0.content { return $0.parentID == nil }; return false }),
                      let corners = scene.worldCorners(of: target.id) else { log("PERF drag: no layer"); break }
                let mid = Vec2(corners.map(\.x).reduce(0, +) / 4, corners.map(\.y).reduce(0, +) / 4)
                let v = canvas.convert(canvas.compositionToView(mid), to: nil)
                let h = window.contentView!.bounds.height
                let start = (x: Double(v.x), y: Double(h - v.y))
                mouse(.leftMouseDown, start.x, start.y)
                let began = CACurrentMediaTime()
                var k = 0
                var worst = 0.0
                var lastT = began
                func step() {
                    let now = CACurrentMediaTime()
                    worst = max(worst, now - lastT); lastT = now
                    guard k < Int(n[0]) else {
                        mouse(.leftMouseUp, start.x + Double(k), start.y + Double(k) / 2)
                        log(String(format: "PERF drag %.1f ms per step, worst %.1f ms (%@)", (now - began) / n[0] * 1000, worst * 1000, target.id.uuidString.prefix(4) as CVarArg))
                        next(); return
                    }
                    k += 1
                    mouse(.leftMouseDragged, start.x + Double(k), start.y + Double(k) / 2)
                    DispatchQueue.main.async { step() }
                }
                step(); return
            case "perfselect":
                // Selects layers in turn, n[0] times, with nothing selected
                // in between, and times each until the next turn of the run loop.
                let ids = controller.project.layers.prefix(20).map(\.id)
                var k = 0
                var times: [Double] = []
                var mark = CACurrentMediaTime()
                func step() {
                    let now = CACurrentMediaTime()
                    if k > 0 { times.append((now - mark) * 1000) }
                    guard k < Int(n[0]) else {
                        let sorted = times.sorted()
                        log(String(format: "PERF select median %.1f ms, worst %.1f ms", sorted[sorted.count / 2], sorted.last ?? 0))
                        next(); return
                    }
                    mark = CACurrentMediaTime()
                    if k % 2 == 0 { controller.select([ids[(k / 2) % ids.count]]) } else { controller.deselectAll() }
                    k += 1
                    DispatchQueue.main.async { step() }
                }
                step(); return
            case "perfdragat":
                // Presses at (n[0], n[1]) and drags right a point a step for n[2] steps.
                let pressed = CACurrentMediaTime()
                mouse(.leftMouseDown, n[0], n[1])
                log(String(format: "PERF press %.1f ms", (CACurrentMediaTime() - pressed) * 1000))
                let began = CACurrentMediaTime()
                var k = 0
                var worst = 0.0
                var lastT = began
                func step() {
                    let now = CACurrentMediaTime()
                    if k > 1 { worst = max(worst, now - lastT) }
                    lastT = now
                    guard k < Int(n[2]) else {
                        mouse(.leftMouseUp, n[0] + Double(k), n[1])
                        log(String(format: "PERF dragat %.1f ms per step, worst %.1f ms", (now - began) / n[2] * 1000, worst * 1000))
                        next(); return
                    }
                    k += 1
                    mouse(.leftMouseDragged, n[0] + Double(k), n[1])
                    DispatchQueue.main.async { step() }
                }
                step(); return
            case "cursor":
                let names: [(String, NSCursor)] = [("arrow", Cursors.arrow), ("crosshair", Cursors.crosshair), ("hand", Cursors.hand),
                    ("grabbed", Cursors.handGrabbed), ("h", Cursors.resizeHorizontal), ("v", Cursors.resizeVertical),
                    ("nwse", Cursors.resizeNWSE), ("nesw", Cursors.resizeNESW), ("rTL", Cursors.rotateTopLeft),
                    ("rTR", Cursors.rotateTopRight), ("rBL", Cursors.rotateBottomLeft), ("rBR", Cursors.rotateBottomRight),
                    ("pen", Cursors.pen), ("penAdd", Cursors.penAdd), ("penMove", Cursors.penMove), ("penConnect", Cursors.penConnect)]
                log("CURSOR " + (names.first { $0.1 === NSCursor.current }?.0 ?? "other") + " size=\(Cursors.arrow.image.size)")
            case "spacedown":
                let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
                window.sendEvent(e)
            case "spaceup":
                let e = NSEvent.keyEvent(with: .keyUp, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
                window.sendEvent(e)
            case "keycode": key("x", UInt16(n[0]))
            case "down": mouse(.leftMouseDown, n[0], n[1])
            case "to": mouse(.leftMouseDragged, n[0], n[1])
            case "up": mouse(.leftMouseUp, n[0], n[1])
            case "seek": controller.seek(to: n[0])
            case "call":
                switch parts[1] {
                case "duplicate": controller.duplicateSelection()
                case "shortcuts": (window.windowController as? EditorWindowController)?.toggleShortcuts(nil)
                case "copy": controller.copySelection()
                case "paste": controller.paste()
                case "undo": controller.store.undoManager.undo()
                case "focuscanvas": controller.editor.focus = .canvas
                case "copyeasing": controller.copyEasing()
                case "pasteeasing": controller.pasteEasing()
                case "exportmovie": (window.windowController as? EditorWindowController)?.exportFile(nil)
                case "exportframe": (window.windowController as? EditorWindowController)?.exportFrame(nil)
                case "staggermenu": (window.windowController as? EditorWindowController)?.staggerActions(nil)
                case "frameselection": controller.frameSelection()
                case "group": controller.groupSelection()
                default: log("unknown call \(parts[1])")
                }
            case "spec":
                log("SPEC " + controller.selectedActions.map { "\($0.name) \(String(format: "%.3f", $0.start))+\(String(format: "%.3f", $0.duration)) \($0.easing) \($0.spec)" }.joined(separator: " | ")
                    .replacingOccurrences(of: "MotionModel.", with: ""))
            case "actions":
                log("ACTIONS " + controller.project.actions.sorted { ($0.targetLayerID.uuidString, $0.rowOrder) < ($1.targetLayerID.uuidString, $1.rowOrder) }
                    .map { "\($0.name)[\(controller.project.layer(withID: $0.targetLayerID)?.name ?? "?") r\($0.rowOrder) \(String(format: "%.3f", $0.start))+\(String(format: "%.3f", $0.duration))\($0.isEnabled ? "" : " off")]" }
                    .joined(separator: " ") + " sel=\(controller.selectedActions.map(\.name))")
            case "wait": wait = n[0]
            case "savepanel":
                if let panel = window.attachedSheet as? NSSavePanel {
                    let url = URL(fileURLWithPath: parts[1])
                    panel.directoryURL = url.deletingLastPathComponent()
                    panel.nameFieldStringValue = url.lastPathComponent
                    log("PANEL name=\(panel.nameFieldStringValue) types=\(panel.allowedContentTypes.map(\.identifier))")
                    window.endSheet(panel, returnCode: .OK)
                } else { log("PANEL none") }
            case "canvasundo":
                controller.canvas?.undo(nil)
            case "text":
                if case .text(let t)? = controller.selectedLayers.first?.content {
                    let c = controller.canvas
                    log("TEXT \(t.text.debugDescription) name=\(controller.selectedLayers.first!.name) editing=\(c?.isEditingText ?? false) sel=\(c?.textSession.map { "\($0.text.selection)" } ?? "-") undo=\(controller.store.undoManager.undoActionName)")
                } else { log("TEXT none") }
            case "path":
                // The selected shape's points and style, and what the canvas
                // is doing with them; with "xy", each point's place in the
                // window, in the steps' coordinates, to click on.
                guard let layer = controller.selectedLayers.first, case .shape(let shape) = layer.content else { log("PATH none"); break }
                let c = controller.canvas
                let session = c?.pathSession
                func f(_ v: Double) -> String { String(format: "%.1f", v) }
                var line = "PATH \(layer.name) "
                if case .path(let p) = shape.geometry {
                    line += p.subpaths.map { sub in
                        (sub.isClosed ? "closed[" : "open[") + sub.points.map { pt in
                            "\(f(pt.position.x)),\(f(pt.position.y))" + (pt.inHandle == .zero && pt.outHandle == .zero ? ""
                                : " i\(f(pt.inHandle.x)),\(f(pt.inHandle.y)) o\(f(pt.outHandle.x)),\(f(pt.outHandle.y))")
                        }.joined(separator: "; ") + "]"
                    }.joined(separator: " ")
                } else {
                    line += "geometry=\(shape.geometry)".replacingOccurrences(of: "MotionModel.", with: "")
                }
                line += " size=\(f(layer.size.width)),\(f(layer.size.height)) pos=\(f(layer.transform.position.x)),\(f(layer.transform.position.y))"
                line += " anchor=\(f(layer.transform.anchor.x)),\(f(layer.transform.anchor.y)) fills=\(shape.fills.count) strokes=\(shape.strokes.count)"
                line += " editing=\(c?.isEditingPoints ?? false) drawing=\(session?.drawingFrom.map { "\($0.subpath).\($0.index)" } ?? "-")"
                line += " picked=\(session?.selected.sorted().map { "\($0.subpath).\($0.index)" } ?? []) undo=\(controller.store.undoManager.undoActionName)"
                if parts.count > 1, parts[1] == "xy", let c, let s = session, let path = c.sessionPath(s), let t = c.pathTransform(s) {
                    let h = window.contentView!.bounds.height
                    func xy(_ p: Vec2) -> String {
                        let v = c.convert(c.compositionToView(t.apply(p)), to: nil)
                        return "\(Int(v.x.rounded())),\(Int((h - v.y).rounded()))"
                    }
                    line += " xy=" + PathEditing.refs(in: path).map { ref -> String in
                        let p = PathEditing.point(ref, in: path)!
                        return "\(ref.subpath).\(ref.index)@\(xy(p.position))"
                            + (p.inHandle == .zero ? "" : " in@\(xy(p.position + p.inHandle))")
                            + (p.outHandle == .zero ? "" : " out@\(xy(p.position + p.outHandle))")
                    }.joined(separator: " ")
                }
                log(line)
            case "library":
                // The home screen's folders and projects, each with its folder.
                let lib = HomeWindowController.shared.library
                log("LIBRARY folders=\(lib.folders.map { "\($0.name)(\(lib.count(in: $0)))" }) shown=\(lib.selectedFolder?.lastPathComponent ?? "All") items=\(lib.items.map { "\($0.folder?.lastPathComponent ?? "-")/\($0.name)" }.sorted())")
            case "moveproject":
                // Moves a home screen project into a folder by name, or out with "-",
                // as dropping its card on a folder or All Projects does.
                let lib = HomeWindowController.shared.library
                if let item = lib.items.first(where: { $0.name == parts[1] }) {
                    lib.move(item.url, to: parts[2] == "-" ? nil : lib.folders.first { $0.name == parts[2] }?.url)
                } else { log("no project \(parts[1])") }
            case "showfolder":
                let lib = HomeWindowController.shared.library
                lib.selectedFolder = parts[1] == "-" ? nil : lib.folders.first { $0.name == parts[1] }?.url
            case "onboarding":
                // Raises the onboarding card, as Help > Show Onboarding does.
                OnboardingState.shared.show()
            case "home":
                // Home, as the layers panel's button does.
                HomeWindowController.shared.showWindow(nil)
            case "openfile":
                // Opens a project in the one window, as a double-click in the Finder does.
                NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: parts[1]), display: true) { _, _, error in
                    if let error { log("OPEN error \(error.localizedDescription)") }
                }
            case "import":
                controller.importMedia(parts.dropFirst().map { URL(fileURLWithPath: $0) })
            case "pastefigma":
                // As Paste with a copy from the Figma plugin on the clipboard,
                // without touching the clipboard in use.
                guard let text = try? String(contentsOfFile: parts[1], encoding: .utf8) else { log("PASTEFIGMA unreadable"); break }
                controller.pasteFromFigma(text)
            case "composition":
                let c = controller.project.composition
                log("COMPOSITION \(c.width)x\(c.height) notice=\(controller.editor.notice?.text ?? "-")")
            case "replace":
                // As Replace in the inspector, with the file handed in rather
                // than chosen in the panel, which runs in another process.
                guard let id = controller.selection.first else { log("REPLACE none"); break }
                controller.replaceMedia(of: id, with: URL(fileURLWithPath: parts[1]))
            case "fillpicture":
                guard let id = controller.selection.first else { log("FILLPICTURE none"); break }
                controller.fillWithPicture(id, from: URL(fileURLWithPath: parts[1]))
            case "mode":
                guard let id = controller.selection.first, let mode = ImageScaleMode(rawValue: parts[1]) else { log("MODE none"); break }
                controller.setPictureMode(id, mode)
            case "turn":
                guard let id = controller.selection.first else { log("TURN none"); break }
                controller.turnPicture(id)
            case "blend":
                guard let mode = BlendMode(rawValue: parts[1]) else { log("BLEND unknown"); break }
                controller.editSelection { $0.blendMode = mode }
            case "effect":
                // Adds a drop or inner shadow, as the Effects menu does, with
                // an offset and colour to see: effect inner|drop DX DY BLUR HEX.
                let shadow = DropShadow(color: RGBA(hex: parts[5]) ?? .black, offset: Vec2(n[0], n[1]), blur: n[2], opacity: 1)
                controller.editSelection { $0.effects.append(Effect(kind: parts[1] == "inner" ? .innerShadow(shadow) : .dropShadow(shadow))) }
            case "tree":
                // Every layer, indented under its parent, with its kind, box,
                // place in its parent and clipping.
                func walk(_ layers: [Layer], _ depth: Int) {
                    for l in layers.reversed() {
                        let kind = l.isFrame ? "frame" : l.isGroup ? "group" : l.picture != nil ? "picture" : "\(l.content)".prefix(5).description
                        var clip = ""
                        if case .group(let g) = l.content { clip = g.clipsContent ? " clips" : "" }
                        let fills = l.look.map { " fills=\($0.fills.count) strokes=\($0.strokes.count)" } ?? ""
                        log("TREE " + String(repeating: "  ", count: depth) + "\(l.name) \(kind) pos=\(Int(l.transform.position.x)),\(Int(l.transform.position.y)) size=\(Int(l.size.width))x\(Int(l.size.height)) scale=\(l.transform.scale.x)\(clip)\(fills)")
                        walk(l.children, depth + 1)
                    }
                }
                walk(controller.project.layers, 0)
                log("TREE undo=\(controller.store.undoManager.undoActionName) sel=\(controller.selectedLayers.map(\.name))")
            case "picture":
                // The selected layer's picture or video, and while cropping,
                // where the picture's corners and the layer's are in the
                // window, in the steps' coordinates, to drag.
                guard let layer = controller.selectedLayers.first else { log("PICTURE none"); break }
                func f(_ v: Double) -> String { String(format: "%.3f", v) }
                var line = "PICTURE \(layer.name) size=\(Int(layer.size.width))x\(Int(layer.size.height))"
                line += " pos=\(Int(layer.transform.position.x)),\(Int(layer.transform.position.y))"
                if let (i, p) = layer.picture {
                    let file = controller.project.media.first { $0.id == p.mediaID }?.originalName ?? "?"
                    line += " fill=\(i) file=\(file) mode=\(p.mode.rawValue) turns=\(p.turns) opacity=\(f(p.opacity))"
                    line += " crop=\(f(p.crop.x)),\(f(p.crop.y)),\(f(p.crop.width)),\(f(p.crop.height)) tile=\(f(p.tileScale))"
                } else if case .video(let v) = layer.content {
                    let file = controller.project.media.first { $0.id == v.mediaID }?.originalName ?? "?"
                    line += " video=\(file) fit=\(v.fit.rawValue)"
                } else {
                    line += " no picture"
                }
                line += " actions=\(controller.project.actions(on: layer.id).count) media=\(controller.project.media.count)"
                line += " cropping=\(controller.canvas?.isCropping ?? false) undo=\(controller.store.undoManager.undoActionName)"
                if let c = controller.canvas, let marks = c.cropMarks(), let box = c.cropBoxCorners {
                    let h = window.contentView!.bounds.height
                    func xy(_ p: CGPoint) -> String {
                        let v = c.convert(p, to: nil)
                        return "\(Int(v.x.rounded())),\(Int((h - v.y).rounded()))"
                    }
                    line += " picturexy=" + marks.corners.map(xy).joined(separator: " ") + " boxxy=" + box.map(xy).joined(separator: " ")
                }
                log(line)
            case "save":
                // Saving runs on the main thread, so its time is how long the app froze.
                let began = Date()
                (window.windowController?.document as? NSDocument)?.autosave(withImplicitCancellability: false) { _ in
                    log("SAVE \(Int(Date().timeIntervalSince(began) * 1000)) ms")
                }
            case "waitexport":
                func poll() {
                    if controller.editor.exports.isExporting { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { poll() } } else { next() }
                }
                poll(); return
            default: log("unknown step \(steps[i])")
            }
            next()
        }
    }
}
