import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// The selected action's fields and nothing else: when it runs, how it
/// eases, and its values. Several actions of one kind edit together; mixed
/// kinds share their timing and easing only.
struct ActionInspector: View {
    let controller: EditorController
    let actions: [Action]

    private var first: Action { actions[0] }
    private var sameKind: Bool { actions.allSatisfy { $0.spec.kind == first.spec.kind } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(title: actions.count == 1 ? first.name : sameKind ? first.spec.kind.defaultName : "Actions") {}
            VStack(alignment: .leading, spacing: 10) {
                TimingFields(controller: controller, actions: actions)
                // A Play runs at the clip's own speed, so it has no easing.
                if actions.contains(where: { !$0.isInstant && $0.spec.kind != .play }) {
                    EasingFields(controller: controller, actions: actions)
                }
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.bottom, Theme.panelPad)

            if sameKind {
                PanelDivider()
                ValueFields(controller: controller, action: first, inherited: controller.inheritedState(for: first))
                    .padding(Theme.panelPad)
            }
        }
    }
}

// MARK: - Timing

private struct TimingFields: View {
    let controller: EditorController
    let actions: [Action]

    var body: some View {
        let frames = controller.editor.showsFrames
        let rate = controller.frameRate
        let first = actions[0]
        HStack(spacing: 8) {
            UnitField(unit: "Start", value: frames ? Double(rate.frame(at: first.start)) : first.start,
                      decimals: frames ? 0 : 2, suffix: frames ? "f" : "s", accepts: { $0 >= 0 }) { v in
                let t = rate.snapped(frames ? rate.time(ofFrame: Int(v.rounded())) : v)
                controller.editActions("Change Timing") { $0.start = max(t, 0) }
            }
            .help("When it starts, from the beginning of the scene.")
            if first.spec.kind != .visibility {
                UnitField(unit: "Length", value: frames ? Double(rate.frame(at: first.duration)) : first.duration,
                          decimals: frames ? 0 : 2, suffix: frames ? "f" : "s", accepts: { $0 >= 0 }) { v in
                    let d = rate.snapped(frames ? rate.time(ofFrame: Int(v.rounded())) : v)
                    controller.editActions("Change Timing") { $0.duration = max(d, 0) }
                }
                .help("How long it runs. 0 makes the change instant.")
            }
        }
    }
}

// MARK: - Easing

private struct EasingFields: View {
    let controller: EditorController
    let actions: [Action]

    private var shared: Easing? {
        let first = actions[0].easing
        return actions.allSatisfy { $0.easing == first } ? first : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuRow(label: "Easing", value: shared.map(Self.name) ?? "Mixed", entries: entries)
            switch shared {
            case .preset(let preset, let intensity) where preset != .none:
                SliderRow(label: "Intensity", value: intensity * 100, range: 0...100,
                          readout: { "\(Int($0.rounded()))%" },
                          onChange: { v in controller.updateActions { $0.easing = .preset(preset, intensity: v / 100) } },
                          onBegin: { controller.begin("Easing") },
                          onEnd: { controller.end() })
            case .custom(let curve):
                CurveEditor(curve: curve, controller: controller)
                    .frame(height: 150)
            default:
                EmptyView()
            }
        }
    }

    static func name(_ easing: Easing) -> String {
        switch easing {
        case .preset(let preset, _): return preset.title
        case .custom: return "Custom"
        }
    }

    private func entries() -> [MenuEntry] {
        var list: [MenuEntry] = EasingPreset.allCases.map { preset in
            .item(preset.title, checked: { if case .preset(preset, _) = shared { return true } else { return false } }()) {
                controller.editActions("Easing") { action in
                    // A new preset keeps the intensity already chosen.
                    var intensity = 0.5
                    if case .preset(_, let i) = action.easing { intensity = i }
                    action.easing = .preset(preset, intensity: intensity)
                }
            }
        }
        list.append(.separator)
        list.append(.item("Custom", checked: { if case .custom = shared { return true } else { return false } }()) {
            controller.editActions("Easing") { action in
                // Starts from the curve the preset was making, so nothing jumps.
                if case .preset(let p, let i) = action.easing {
                    action.easing = .custom(p == .spring ? .easeInOut : p.curve(intensity: i))
                }
            }
        })
        return list
    }
}

extension EasingPreset {
    var title: String {
        switch self {
        case .none: return "None"
        case .smooth: return "Smooth"
        case .slowDown: return "Slow down"
        case .accelerate: return "Accelerate"
        case .overshoot: return "Overshoot"
        case .spring: return "Spring"
        }
    }
}

/// The custom timing curve, time across and progress up, with its two
/// handles to drag. Room above and below leaves space for overshoot.
private struct CurveEditor: View {
    let curve: CubicBezier
    let controller: EditorController

    @State private var grabbed: Int?

    private let lowest = -0.3, highest = 1.3
    private let pad: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, _ in
                let a = point(0, 1, size), b = point(1, 0, size)
                context.stroke(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)),
                               with: .color(Theme.border), lineWidth: 1)
                var diagonal = Path()
                diagonal.move(to: point(0, 0, size))
                diagonal.addLine(to: point(1, 1, size))
                context.stroke(diagonal, with: .color(Theme.border), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

                var shape = Path()
                shape.move(to: point(0, 0, size))
                for i in 1...80 {
                    let x = Double(i) / 80
                    shape.addLine(to: point(x, curve.value(at: x), size))
                }
                context.stroke(shape, with: .color(Theme.accent), lineWidth: 2)

                let p1 = point(curve.x1, curve.y1, size), p2 = point(curve.x2, curve.y2, size)
                var arms = Path()
                arms.move(to: point(0, 0, size)); arms.addLine(to: p1)
                arms.move(to: point(1, 1, size)); arms.addLine(to: p2)
                context.stroke(arms, with: .color(Theme.textTertiary), lineWidth: 1)
                for p in [p1, p2] {
                    let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                    context.fill(dot, with: .color(.white))
                    context.stroke(dot, with: .color(Theme.accent), lineWidth: 1.5)
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.canvas))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if grabbed == nil {
                        let p1 = point(curve.x1, curve.y1, size), p2 = point(curve.x2, curve.y2, size)
                        grabbed = hypot(g.startLocation.x - p1.x, g.startLocation.y - p1.y)
                            <= hypot(g.startLocation.x - p2.x, g.startLocation.y - p2.y) ? 1 : 2
                        controller.begin("Easing Curve")
                    }
                    let v = value(at: g.location, size)
                    var c = curve
                    if grabbed == 1 { c.x1 = v.x; c.y1 = v.y } else { c.x2 = v.x; c.y2 = v.y }
                    controller.updateActions { $0.easing = .custom(c) }
                }
                .onEnded { _ in
                    grabbed = nil
                    controller.end()
                })
        }
        .help("Drag the handles. Across is time, up is how far along the action is.")
    }

    private func point(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: pad + x * (size.width - pad * 2),
                y: pad + (highest - y) / (highest - lowest) * (size.height - pad * 2))
    }

    /// Handles keep to the square's width, since time cannot run backwards
    /// inside an action, but can go well above and below it.
    private func value(at p: CGPoint, _ size: CGSize) -> (x: Double, y: Double) {
        let x = (p.x - pad) / (size.width - pad * 2)
        let y = highest - (p.y - pad) / (size.height - pad * 2) * (highest - lowest)
        return (min(max(x, 0), 1), min(max(y, -1), 2))
    }
}

// MARK: - Values

/// The kind's own fields: To or By where it has them, the starting value
/// (empty inherits, and shows what it would inherit), and the end value.
private struct ValueFields: View {
    let controller: EditorController
    let action: Action
    let inherited: LayerState?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch action.spec {
            case .move(let m): move(m)
            case .scale(let s): scale(s)
            case .rotate(let r): rotate(r)
            case .opacity(let o): opacity(o)
            case .resize(let r): resize(r)
            case .visibility(let v): visibility(v)
            default: StyleValueFields(controller: controller, action: action, inherited: inherited)
            }
        }
    }

    // MARK: Move

    @ViewBuilder private func move(_ m: MoveAction) -> some View {
        let from = inherited?.position ?? .zero
        modeRow(m.mode)
        LabeledRow(label: "From") {
            OptionalField(unit: "X", value: m.initial?.x, placeholder: from.x) { v in
                editMove("Starting Value") { m, s in m.initial = v.map { Vec2($0, (m.initial ?? s.position).y) } }
            }
            OptionalField(unit: "Y", value: m.initial?.y, placeholder: from.y) { v in
                editMove("Starting Value") { m, s in m.initial = v.map { Vec2((m.initial ?? s.position).x, $0) } }
            }
            clearButton(m.initial != nil) { editMove("Starting Value") { m, _ in m.initial = nil } }
        }
        .help("Where it starts. Empty starts from wherever the layer is when the action begins.")
        LabeledRow(label: m.mode == .to ? "To" : "By") {
            UnitField(unit: "X", value: m.end.x) { v in editMove("Move") { m, _ in m.end.x = v } }
            UnitField(unit: "Y", value: m.end.y) { v in editMove("Move") { m, _ in m.end.y = v } }
            Color.clear.frame(width: Theme.control)
        }
        .help(m.mode == .to ? "Where it ends, in the layer's parent's space." : "How far it moves from where it starts.")
        HStack {
            Text("Curved path")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            PillToggle(isOn: m.curve != nil) {
                editMove(m.curve == nil ? "Curve Path" : "Straighten Path") { m, s in
                    if m.curve == nil {
                        let p = ActionGeometry.path(of: m, from: s.position)
                        m.curve = ActionGeometry.defaultCurve(from: p.start, to: p.end)
                    } else {
                        m.curve = nil
                    }
                }
            }
        }
        .help("Bends the path. Drag its handles on the canvas.")
    }

    private func editMove(_ name: String, _ change: @escaping (inout MoveAction, LayerState) -> Void) {
        controller.editActions(name) { a in
            guard case .move(var m) = a.spec, let state = controller.inheritedState(for: a) else { return }
            change(&m, state)
            a.spec = .move(m)
        }
    }

    // MARK: Scale

    @ViewBuilder private func scale(_ s: ScaleAction) -> some View {
        let from = inherited?.scale ?? .one
        modeRow(s.mode)
        LabeledRow(label: "From") {
            if s.isLinked {
                OptionalField(unit: "S", value: s.initial.map { $0.x * 100 }, placeholder: from.x * 100, decimals: 1, suffix: "%") { v in
                    editScale("Starting Value") { s, _ in s.initial = v.map { Vec2($0 / 100, $0 / 100) } }
                }
            } else {
                OptionalField(unit: "X", value: s.initial.map { $0.x * 100 }, placeholder: from.x * 100, decimals: 1, suffix: "%") { v in
                    editScale("Starting Value") { s, st in s.initial = v.map { Vec2($0 / 100, (s.initial ?? st.scale).y) } }
                }
                OptionalField(unit: "Y", value: s.initial.map { $0.y * 100 }, placeholder: from.y * 100, decimals: 1, suffix: "%") { v in
                    editScale("Starting Value") { s, st in s.initial = v.map { Vec2((s.initial ?? st.scale).x, $0 / 100) } }
                }
            }
            clearButton(s.initial != nil) { editScale("Starting Value") { s, _ in s.initial = nil } }
        }
        .help("The scale it starts at. Empty starts from the layer's scale when the action begins.")
        LabeledRow(label: s.mode == .to ? "To" : "By") {
            if s.isLinked {
                UnitField(unit: "S", value: s.end.x * 100, decimals: 1, suffix: "%") { v in
                    editScale("Scale") { s, _ in s.end = Vec2(v / 100, v / 100) }
                }
            } else {
                UnitField(unit: "X", value: s.end.x * 100, decimals: 1, suffix: "%") { v in editScale("Scale") { s, _ in s.end.x = v / 100 } }
                UnitField(unit: "Y", value: s.end.y * 100, decimals: 1, suffix: "%") { v in editScale("Scale") { s, _ in s.end.y = v / 100 } }
            }
            IconButton(icon: s.isLinked ? .link : .unlink, help: s.isLinked ? "Unlink width and height" : "Link width and height") {
                editScale("Link Scale") { s, _ in
                    s.isLinked.toggle()
                    if s.isLinked { s.end.y = s.end.x; s.initial = s.initial.map { Vec2($0.x, $0.x) } }
                }
            }
        }
        .help(s.mode == .to ? "The scale it ends at." : "What it multiplies the starting scale by.")
    }

    private func editScale(_ name: String, _ change: @escaping (inout ScaleAction, LayerState) -> Void) {
        controller.editActions(name) { a in
            guard case .scale(var s) = a.spec, let state = controller.inheritedState(for: a) else { return }
            change(&s, state)
            a.spec = .scale(s)
        }
    }

    // MARK: Rotate

    @ViewBuilder private func rotate(_ r: RotateAction) -> some View {
        modeRow(r.mode)
        LabeledRow(label: "From") {
            OptionalField(unit: "R", value: r.initial, placeholder: inherited?.rotation ?? 0, decimals: 1, suffix: "°") { v in
                editRotate("Starting Value") { $0.initial = v }
            }
            clearButton(r.initial != nil) { editRotate("Starting Value") { $0.initial = nil } }
        }
        .help("The angle it starts at. Empty starts from the layer's angle when the action begins.")
        LabeledRow(label: r.mode == .to ? "To" : "By") {
            UnitField(unit: "R", value: r.end, decimals: 1, suffix: "°") { v in editRotate("Rotate") { $0.end = v } }
            Color.clear.frame(width: Theme.control)
        }
        .help(r.mode == .to ? "The angle it ends at. 720° spins twice." : "How far it turns. Negative turns anticlockwise.")
    }

    private func editRotate(_ name: String, _ change: @escaping (inout RotateAction) -> Void) {
        controller.editActions(name) { a in
            guard case .rotate(var r) = a.spec else { return }
            change(&r)
            a.spec = .rotate(r)
        }
    }

    // MARK: Opacity

    @ViewBuilder private func opacity(_ o: OpacityAction) -> some View {
        LabeledRow(label: "From") {
            OptionalField(value: o.initial.map { $0 * 100 }, placeholder: (inherited?.opacity ?? 1) * 100,
                          suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                editOpacity("Starting Value") { $0.initial = v.map { $0 / 100 } }
            }
            clearButton(o.initial != nil) { editOpacity("Starting Value") { $0.initial = nil } }
        }
        .help("The opacity it starts at. Set it to fade a layer in from nothing, before the action begins.")
        LabeledRow(label: "To") {
            UnitField(value: o.end * 100, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                editOpacity("Opacity") { $0.end = v / 100 }
            }
            Color.clear.frame(width: Theme.control)
        }
    }

    private func editOpacity(_ name: String, _ change: @escaping (inout OpacityAction) -> Void) {
        controller.editActions(name) { a in
            guard case .opacity(var o) = a.spec else { return }
            change(&o)
            a.spec = .opacity(o)
        }
    }

    // MARK: Resize

    @ViewBuilder private func resize(_ r: ResizeAction) -> some View {
        let from = inherited?.size ?? Size2(0, 0)
        LabeledRow(label: "From") {
            OptionalField(unit: "W", value: r.initial?.width, placeholder: from.width, accepts: { $0 >= 0 }) { v in
                editResize("Starting Value") { r, st in r.initial = v.map { Size2($0, (r.initial ?? st.size).height) } }
            }
            OptionalField(unit: "H", value: r.initial?.height, placeholder: from.height, accepts: { $0 >= 0 }) { v in
                editResize("Starting Value") { r, st in r.initial = v.map { Size2((r.initial ?? st.size).width, $0) } }
            }
            clearButton(r.initial != nil) { editResize("Starting Value") { r, _ in r.initial = nil } }
        }
        .help("The size it starts at. Empty starts from the layer's size when the action begins.")
        LabeledRow(label: "To") {
            UnitField(unit: "W", value: r.end.width, accepts: { $0 >= 0 }) { v in
                editResize("Resize") { r, _ in
                    if r.isLinked, r.end.width > 0 { r.end.height *= v / r.end.width }
                    r.end.width = v
                }
            }
            UnitField(unit: "H", value: r.end.height, accepts: { $0 >= 0 }) { v in
                editResize("Resize") { r, _ in
                    if r.isLinked, r.end.height > 0 { r.end.width *= v / r.end.height }
                    r.end.height = v
                }
            }
            IconButton(icon: r.isLinked ? .link : .unlink, help: r.isLinked ? "Unlink width and height" : "Keep width and height in proportion") {
                editResize("Link Size") { r, _ in r.isLinked.toggle() }
            }
        }
        .help("The size it ends at. The layer grows and shrinks around its anchor.")
    }

    private func editResize(_ name: String, _ change: @escaping (inout ResizeAction, LayerState) -> Void) {
        controller.editActions(name) { a in
            guard case .resize(var r) = a.spec, let state = controller.inheritedState(for: a) else { return }
            change(&r, state)
            a.spec = .resize(r)
        }
    }

    // MARK: Hide/Show

    private func visibility(_ v: VisibilityAction) -> some View {
        SegmentRow(selection: v.isVisible, options: [false, true], title: { $0 ? "Show" : "Hide" }) { show in
            controller.editActions(show ? "Show" : "Hide") { a in
                a.spec = .visibility(VisibilityAction(isVisible: show))
                // A name the user never changed follows what it does.
                if a.name == "Hide" || a.name == "Show" || a.name == ActionKind.visibility.defaultName {
                    a.name = show ? "Show" : "Hide"
                }
            }
        }
        .help("Hides or shows the layer at the action's start. A layer whose first one is Show stays hidden until it.")
    }

    // MARK: Shared

    private func modeRow(_ mode: ActionMode) -> some View {
        SegmentRow(selection: mode, options: ActionMode.allCases, title: { $0 == .to ? "To" : "By" }) { new in
            controller.editActions("Change Mode") { a in
                guard let state = controller.inheritedState(for: a) else { return }
                a = ActionGeometry.switchingMode(a, to: new, from: state)
            }
        }
        .help("To ends at a fixed value. By changes the value it starts from by an amount, so it follows the layer wherever it is designed.")
    }

    /// Empties the starting value, so it inherits again. A spacer when
    /// there is nothing to clear, so the fields keep their widths.
    @ViewBuilder private func clearButton(_ visible: Bool, _ action: @escaping () -> Void) -> some View {
        if visible {
            IconButton(icon: .close, help: "Start from wherever the layer is instead", action: action)
        } else {
            Color.clear.frame(width: Theme.control)
        }
    }
}
