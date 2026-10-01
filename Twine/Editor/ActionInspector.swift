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
    /// The New Action menu, for adding another action to the selected layers
    /// without leaving this one.
    var newActions: [MenuEntry] = []
    var pickPreset: (() -> Void)? = nil
    /// Opens the picker to swap the selected preset bars for another; nil
    /// when none is selected.
    var swapPreset: (() -> Void)? = nil
    /// A sound or video whose Play bars are selected: its level shows under
    /// the fields.
    var sound: Layer? = nil

    private var first: Action { actions[0] }
    /// Presets count as one kind only when they are the same preset.
    private var sameKind: Bool { actions.allSatisfy { $0.spec.kind == first.spec.kind && $0.preset == first.preset } }

    private var kindName: String {
        first.preset.map { Presets.preset($0.preset).name } ?? first.spec.kind.defaultName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(title: actions.count == 1 ? first.name : sameKind ? kindName : "Actions") {}
            VStack(alignment: .leading, spacing: 10) {
                TimingFields(controller: controller, actions: actions)
                // A Play runs at the clip's own speed, and a shake keeps its
                // jolts' own easing, so neither has any.
                if actions.contains(where: { !$0.isInstant && $0.spec.kind != .play
                                             && $0.preset.map { PresetRecipe.usesEasing($0.preset) } ?? true }) {
                    EasingFields(controller: controller, actions: actions)
                }
                if actions.allSatisfy(\.canMotionBlur) {
                    MotionBlurFields(controller: controller, actions: actions)
                }
            }
            .gridBody()
            .padding(.bottom, Theme.panelPad)

            if sameKind, let settings = first.preset {
                // A preset with nothing to set but its timing, and no way to
                // turn it In or Out or move a text letter by letter, shows
                // nothing more.
                let onText = !settings.preset.movesWholeLayer && actions.allSatisfy { controller.project.layer(withID: $0.targetLayerID)?.isText == true }
                if !Presets.controls(for: settings.preset).isEmpty || settings.preset.reversed != nil || onText {
                    PanelDivider()
                    PresetFields(controller: controller, settings: settings, onText: onText)
                        .gridBody()
                        .padding(.vertical, Theme.panelPad)
                }
            } else if sameKind {
                PanelDivider()
                ValueFields(controller: controller, action: first, inherited: controller.inheritedState(for: first))
                    .gridBody()
                    .padding(.vertical, Theme.panelPad)
            }

            if let sound {
                PanelDivider()
                LayerSoundSection(layer: sound, controller: controller)
            }

            // A preset bar can become another where it stands.
            if let swapPreset {
                PanelDivider()
                PanelButton(title: "Swap Preset", icon: .swap, disabled: controller.swappablePresets.isEmpty, action: swapPreset)
                    .help("Picks another preset to put in this one's place, keeping when it starts.")
                    .gridBody()
                    .padding(.vertical, Theme.panelPad)
            }

            // Several actions picked: gather them into a timeline scene.
            if actions.count > 1, controller.selectedScene?.actionIDs.count != actions.count {
                PanelDivider()
                PanelButton(title: "Group into Scene", icon: .plus) { controller.groupSelectedActionsIntoScene() }
                    .help("Gathers these actions under one row on the timeline that shows how long they run, "
                          + "folds, and moves or stretches them together.")
                    .gridBody()
                    .padding(.vertical, Theme.panelPad)
            }

            // At the end, another action or preset for the same layers, so
            // there is no need to pick the layer again.
            if !newActions.isEmpty || pickPreset != nil {
                PanelDivider()
                AddAnother(newActions: newActions,
                           hasPresets: pickPreset != nil && !controller.availablePresets.isEmpty) { pickPreset?() }
                    .gridBody()
                    .padding(.vertical, Theme.panelPad)
            }
        }
    }
}

/// New Action and Select Preset as two small buttons, one over the other,
/// at the foot of an action's settings: the tiles' choices, kept small
/// since adding is not what this inspector is for.
private struct AddAnother: View {
    let newActions: [MenuEntry]
    let hasPresets: Bool
    let pickPreset: () -> Void

    @Environment(MenuHost.self) private var menus
    @State private var newFrame: CGRect = .zero

    var body: some View {
        VStack(spacing: 6) {
            PanelButton(title: "New Action", icon: .plus, disabled: newActions.isEmpty) {
                menus.show(newActions, at: CGPoint(x: newFrame.minX, y: newFrame.maxY + 4))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame = $0 }
            .help("Adds another action to the layer at the playhead, half a second long.")
            PanelButton(title: "Select Preset", icon: .presets, disabled: !hasPresets, action: pickPreset)
                .help("Picks a ready-made animation to add to the layer at the playhead.")
        }
    }
}

extension Action {
    /// A preset bar's settings, nil for any other action.
    var preset: PresetAction? {
        if case .preset(let p) = spec { return p }
        return nil
    }
}

// MARK: - Presets

/// What a preset offers to set, below its timing and easing: only the
/// settings that preset uses, each starting at the preset's own value.
private struct PresetFields: View {
    let controller: EditorController
    let settings: PresetAction
    /// Every bar is on a text, so it can move the text letter by letter.
    var onText = false

    private var kind: PresetKind { settings.preset }
    private var own: PresetAction { PresetRecipe.defaults(kind) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A preset that brings a layer on turns into its twin that takes
            // it off, keeping its settings.
            if let other = kind.reversed {
                let into = kind.entering == true ? kind : other
                SegmentRow(selection: kind, options: [into, into.reversed ?? other],
                           title: { $0.entering == true ? "In" : "Out" }) { turn(to: $0) }
                    .help("In brings the layer on; Out takes it off.")
            }
            ForEach(Presets.controls(for: kind), id: \.self) { control in
                row(control)
            }
            if onText { textRows }
        }
    }

    /// Whether the whole text moves, or its letters, words or lines one by
    /// one, in what order and how far apart.
    @ViewBuilder private var textRows: some View {
        Text("Text animation")
            .font(ThemeFont.labelStrong)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 4)
        LabeledRow(label: "Apply to") {
            MenuField(value: Self.title(settings.unit), entries: {
                ([nil] + TextUnit.allCases.map(Optional.some)).map { unit in
                    .item(Self.title(unit), checked: unit == settings.unit) { setUnit(unit) }
                }
            }, height: Theme.control)
        }
        .help("Moves the whole text, or each letter, word or line in turn.")
        if settings.unit != nil {
            LabeledRow(label: "Order") {
                MenuField(value: Self.title(settings.order ?? .forward), entries: {
                    TextOrder.allCases.map { order in
                        .item(Self.title(order), checked: order == (settings.order ?? .forward)) {
                            edit("Order") { $0.order = order }
                        }
                    }
                }, height: Theme.control)
            }
            .help("Which go first. Random shuffles them, the same way every time.")
            // A Typewriter spreads its letters over the whole bar, so its
            // length sets the pace.
            if !PresetRecipe.isInstant(kind) {
                LabeledRow(label: "Delay") {
                    UnitField(value: (settings.delay ?? settings.unit?.delay ?? 0) * 1000, decimals: 0, suffix: "ms",
                              step: 1, accepts: { $0 >= 0 }) { v in edit("Delay") { $0.delay = v / 1000 } }
                }
                .help("The time between one starting and the next. The bar's length holds them all, so a long text on a short bar starts them closer together.")
            }
        }
    }

    private static func title(_ unit: TextUnit?) -> String {
        switch unit {
        case nil: "Whole Text"
        case .letters?: "Letters"
        case .words?: "Words"
        case .lines?: "Lines"
        }
    }

    private static func title(_ order: TextOrder) -> String {
        switch order {
        case .forward: "Forward"
        case .backward: "Backward"
        case .center: "From Center"
        case .edges: "From Edges"
        case .random: "Random"
        }
    }

    /// A distance still at its own value follows the change: a text's
    /// letters travel their type size, the whole text the preset's own.
    private func setUnit(_ unit: TextUnit?) {
        controller.editActions("Apply to \(Self.title(unit))") { a in
            guard case .preset(var p) = a.spec, p.preset == kind,
                  let layer = controller.project.layer(withID: a.targetLayerID) else { return }
            let before = Presets.unitDistance(p, of: layer)
            let kept = p.distance
            p.unit = unit
            if kept == before { p.distance = Presets.unitDistance(p, of: layer) }
            a.spec = .preset(p)
        }
    }

    /// Every selected bar of this preset turned the other way. A name, an
    /// easing or a length still as the preset gave it follows the turn.
    private func turn(to other: PresetKind) {
        guard other != kind else { return }
        let old = kind
        let rate = controller.project.composition.frameRate
        controller.editActions(other.entering == true ? "In" : "Out") { a in
            guard case .preset(var p) = a.spec, p.preset == old else { return }
            p.preset = other
            a.spec = .preset(p)
            if a.name == Presets.name(of: old) { a.name = Presets.name(of: other) }
            if a.easing == PresetRecipe.easing(old) { a.easing = PresetRecipe.easing(other) }
            if abs(a.duration - rate.snapped(PresetRecipe.length(old))) < 1e-6 {
                a.duration = max(rate.snapped(PresetRecipe.length(other)), rate.frameDuration)
            }
        }
    }

    @ViewBuilder private func row(_ control: PresetControl) -> some View {
        switch control {
        case .direction:
            // Its name above, as Easing's is: four choices need the width.
            VStack(alignment: .leading, spacing: 6) {
                Text(isPageTurn ? "Hinge" : kind.entering == false ? "To" : "From")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                SegmentRow(selection: settings.direction ?? own.direction ?? .left, options: PresetDirection.allCases,
                           title: { $0.rawValue.capitalized }, icon: Self.arrow) { d in edit("Direction") { $0.direction = d } }
            }
            .help(isPageTurn ? "The edge it turns on, as a page on its spine."
                  : kind.entering == false ? "Which way it leaves." : "Which side it comes in from.")
        case .distance:
            LabeledRow(label: kind == .bounce ? "Height" : "Distance") {
                UnitField(value: settings.distance ?? own.distance ?? 0, decimals: 0, suffix: "px", accepts: { $0 >= 0 }) { v in
                    edit("Distance") { $0.distance = v }
                }
            }
            .help(kind == .shake ? "How far it shakes each way." : kind == .bounce ? "How high it bounces." : "How far it travels.")
        case .scale:
            LabeledRow(label: kind == .pulse ? "Peak" : kind.entering == false ? "To" : "From") {
                UnitField(value: (settings.scale ?? own.scale ?? 1) * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 }) { v in
                    edit("Scale") { $0.scale = v / 100 }
                }
            }
            .help(kind == .pulse ? "How big it grows before settling back."
                  : kind.entering == false ? "The size it shrinks to, of its own." : "The size it grows from, of its own.")
        case .angle:
            LabeledRow(label: "Angle") {
                UnitField(value: settings.angle ?? own.angle ?? 0, decimals: 0, suffix: "°") { v in edit("Angle") { $0.angle = v } }
            }
            .help(kind == .wiggle ? "How far it tips each way."
                  : kind.entering == false ? "How far it turns on the way out. Negative turns the other way."
                  : "How far it turns on the way in. Negative turns the other way.")
        case .blur:
            LabeledRow(label: "Blur") {
                UnitField(value: settings.blur ?? own.blur ?? 0, decimals: 0, accepts: { $0 >= 0 }) { v in edit("Blur") { $0.blur = v } }
            }
            .help(kind.entering == false ? "How blurred it ends." : "How blurred it starts.")
        case .fades:
            HStack {
                Text("Fade")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                let fades = settings.fades ?? own.fades ?? true
                PillToggle(isOn: fades) { edit(fades ? "Stop Fading" : "Fade") { $0.fades = !fades } }
            }
            .help(kind.entering == false ? "Fades out as it goes." : "Fades in as it comes on.")
        case .corner:
            // Its name above, as Direction's is.
            VStack(alignment: .leading, spacing: 6) {
                Text("Corner")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                SegmentRow(selection: settings.corner ?? own.corner ?? .topRight, options: PresetCorner.allCases,
                           title: Self.title, icon: Self.icon) { c in edit("Corner") { $0.corner = c } }
            }
            .help(kind.entering == false ? "The corner the page lifts from." : "The corner the page comes down from.")
        }
    }

    private static func title(_ corner: PresetCorner) -> String {
        switch corner {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }

    private static func icon(_ corner: PresetCorner) -> Icon {
        switch corner {
        case .topLeft: .cornerTopLeft
        case .topRight: .cornerTopRight
        case .bottomLeft: .cornerBottomLeft
        case .bottomRight: .cornerBottomRight
        }
    }

    /// Each side as an arrow pointing to it.
    private var isPageTurn: Bool { kind == .pageTurnIn || kind == .pageTurnOut }

    private static func arrow(_ side: PresetDirection) -> Icon {
        switch side {
        case .left: .arrowLeft
        case .right: .arrowRight
        case .top: .arrowUp
        case .bottom: .arrowDown
        }
    }

    /// Changes every selected bar of this preset together.
    private func edit(_ name: String, _ change: @escaping (inout PresetAction) -> Void) {
        controller.editActions(name) { a in
            guard case .preset(var p) = a.spec, p.preset == kind else { return }
            change(&p)
            a.spec = .preset(p)
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
        // The names sit above the fields, so the fields keep their whole
        // width for the number.
        HStack(alignment: .top, spacing: 8) {
            named("Start") {
                UnitField(value: frames ? Double(rate.frame(at: first.start)) : first.start,
                          decimals: frames ? 0 : 2, suffix: frames ? "f" : "s", accepts: { $0 >= 0 }) { v in
                    let t = rate.snapped(frames ? rate.time(ofFrame: Int(v.rounded())) : v)
                    controller.editActions("Change Timing") { $0.start = max(t, 0) }
                }
                .help("When it starts, from the beginning of the animation.")
            }
            if first.spec.kind != .visibility {
                named("Duration") {
                    UnitField(value: frames ? Double(rate.frame(at: first.duration)) : first.duration,
                              decimals: frames ? 0 : 2, suffix: frames ? "f" : "s", accepts: { $0 >= 0 }) { v in
                        let d = rate.snapped(frames ? rate.time(ofFrame: Int(v.rounded())) : v)
                        controller.editActions("Change Timing") { $0.duration = max(d, 0) }
                    }
                    .help("How long it runs. 0 makes the change instant.")
                }
            }
        }
    }

    /// A field with its name above it, as a `StackedRow` has.
    private func named(_ label: String, @ViewBuilder field: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(height: 14)
            field()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Easing

/// Motion blur on what the actions move: a switch, and while it is on, how
/// long the shutter stays open.
private struct MotionBlurFields: View {
    let controller: EditorController
    let actions: [Action]

    private var isOn: Bool { actions.allSatisfy { ($0.motionBlur ?? 0) > 0 } }
    private var amount: Double { actions.first?.motionBlur ?? Action.standardMotionBlur }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ToggleRow(label: "Motion blur", isOn: isOn) {
                let on = !isOn
                controller.editActions(on ? "Motion Blur On" : "Motion Blur Off") { a in
                    a.motionBlur = on ? (a.motionBlur ?? Action.standardMotionBlur) : nil
                }
            }
            .help("Smears the layer along its movement while this plays, as a camera's shutter does.")
            if isOn {
                LabeledRow(label: "Amount") {
                    UnitField(value: amount * 100, suffix: "%", accepts: { $0 > 0 && $0 <= 100 }) { v in
                        controller.editActions("Motion Blur") { $0.motionBlur = v / 100 }
                    }
                }
                .help("How long the shutter stays open, as a share of a frame: 50% is a 180° shutter, 100% a whole frame. The higher, the longer the smear.")
            }
        }
    }
}

private struct EasingFields: View {
    let controller: EditorController
    let actions: [Action]

    @Environment(MenuHost.self) private var menus
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    private var shared: Easing? {
        let first = actions[0].easing
        return actions.allSatisfy { $0.easing == first } ? first : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Easing")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            // A real button, so a click always lands.
            Button(action: open) {
                HStack(spacing: 8) {
                    if let shared {
                        EasingPath(easing: shared, low: -0.5, high: 1.5)
                            .stroke(Theme.textSecondary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                            .frame(width: 10, height: 20)
                    }
                    Text(shared?.title ?? "Mixed")
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    IconView(.chevronDown, size: 13)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 8)
                .frame(height: Theme.panelRow + 4)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(hovering ? Theme.panelHover : Theme.panelRaised))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        }
        .padding(.vertical, 2)
    }

    /// The easing card, beside the inspector towards the canvas, level with
    /// the row.
    private func open() {
        let inspectorLeft = frame.minX - Theme.panelPad
        menus.showPopup(at: CGPoint(x: inspectorLeft - Theme.floatGap - Theme.cardWidth, y: frame.minY - 40)) {
            EasingCard(controller: controller)
        }
    }

}

extension Easing {
    /// Its name in the inspector and on the easing card.
    var title: String {
        switch self {
        case .preset(let preset, _): return preset.title
        case .custom: return "Custom"
        }
    }
}

extension EasingPreset {
    var title: String {
        switch self {
        // Files still say none.
        case .none: return "Linear"
        case .smooth: return "Smooth"
        case .natural: return "Natural"
        case .slowDown: return "Slow down"
        case .accelerate: return "Accelerate"
        case .overshoot: return "Overshoot"
        // Jitter's name for it; files still say spring.
        case .spring: return "Elastic"
        case .bounce: return "Bounce"
        case .impulse: return "Impulse"
        case .swing: return "Swing"
        }
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
            case .skew(let k): skew(k)
            case .tilt(let t): tilt(t)
            default: StyleValueFields(controller: controller, action: action, inherited: inherited)
            }
        }
    }

    // MARK: Move

    @ViewBuilder private func move(_ m: MoveAction) -> some View {
        let from = inherited?.position ?? .zero
        StackedRow(label: "From", accessory: { clearButton(m.initial != nil) { editMove("Starting Value") { m, _ in m.initial = nil } } }) {
            OptionalField(unit: "X", value: m.initial?.x, placeholder: from.x) { v in
                editMove("Starting Value") { m, s in m.initial = v.map { Vec2($0, (m.initial ?? s.position).y) } }
            }
            OptionalField(unit: "Y", value: m.initial?.y, placeholder: from.y) { v in
                editMove("Starting Value") { m, s in m.initial = v.map { Vec2((m.initial ?? s.position).x, $0) } }
            }
        }
        .help("Where it starts. Empty starts from wherever the layer is when the action begins.")
        StackedRow(label: m.mode == .to ? "To" : "By", menu: modeEntries(m.mode), swap: swap) {
            UnitField(unit: "X", value: m.end.x) { v in editMove("Move") { m, _ in m.end.x = v } }
            UnitField(unit: "Y", value: m.end.y) { v in editMove("Move") { m, _ in m.end.y = v } }
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
        if m.curve != nil {
            HStack {
                Text("Rotate along path")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                PillToggle(isOn: m.turnsAlongPath) {
                    editMove(m.turnsAlongPath ? "Stop Rotating Along Path" : "Rotate Along Path") { m, _ in m.turnsAlongPath.toggle() }
                }
            }
            .help("Turns the layer as the path turns, from its own angle, as if it were steering along it.")
        }
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
        StackedRow(label: "From", accessory: { clearButton(s.initial != nil) { editScale("Starting Value") { s, _ in s.initial = nil } } }) {
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
        }
        .help("The scale it starts at. Empty starts from the layer's scale when the action begins.")
        StackedRow(label: s.mode == .to ? "To" : "By", menu: modeEntries(s.mode), swap: swap, accessory: {
            IconButton(icon: s.isLinked ? .link : .unlink, help: s.isLinked ? "Unlink width and height" : "Link width and height") {
                editScale("Link Scale") { s, _ in
                    s.isLinked.toggle()
                    if s.isLinked { s.end.y = s.end.x; s.initial = s.initial.map { Vec2($0.x, $0.x) } }
                }
            }
        }) {
            if s.isLinked {
                UnitField(unit: "S", value: s.end.x * 100, decimals: 1, suffix: "%") { v in
                    editScale("Scale") { s, _ in s.end = Vec2(v / 100, v / 100) }
                }
            } else {
                UnitField(unit: "X", value: s.end.x * 100, decimals: 1, suffix: "%") { v in editScale("Scale") { s, _ in s.end.x = v / 100 } }
                UnitField(unit: "Y", value: s.end.y * 100, decimals: 1, suffix: "%") { v in editScale("Scale") { s, _ in s.end.y = v / 100 } }
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
        StackedRow(label: "From", accessory: { clearButton(r.initial != nil) { editRotate("Starting Value") { $0.initial = nil } } }) {
            OptionalField(unit: "R", value: r.initial, placeholder: inherited?.rotation ?? 0, decimals: 1, suffix: "°") { v in
                editRotate("Starting Value") { $0.initial = v }
            }
        }
        .help("The angle it starts at. Empty starts from the layer's angle when the action begins.")
        StackedRow(label: r.mode == .to ? "To" : "By", menu: modeEntries(r.mode), swap: swap) {
            UnitField(unit: "R", value: r.end, decimals: 1, suffix: "°") { v in editRotate("Rotate") { $0.end = v } }
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

    // MARK: Skew

    @ViewBuilder private func skew(_ k: SkewAction) -> some View {
        let from = inherited?.skew ?? .zero
        StackedRow(label: "From", accessory: { clearButton(k.initial != nil) { editSkew("Starting Value") { k, _ in k.initial = nil } } }) {
            OptionalField(unit: "X", value: k.initial?.x, placeholder: from.x, decimals: 1, suffix: "°") { v in
                editSkew("Starting Value") { k, s in k.initial = v.map { Vec2($0, (k.initial ?? s.skew).y) } }
            }
            OptionalField(unit: "Y", value: k.initial?.y, placeholder: from.y, decimals: 1, suffix: "°") { v in
                editSkew("Starting Value") { k, s in k.initial = v.map { Vec2((k.initial ?? s.skew).x, $0) } }
            }
        }
        .help("The slant it starts at. Empty starts from the layer's slant when the action begins.")
        StackedRow(label: k.mode == .to ? "To" : "By", menu: modeEntries(k.mode), swap: swap) {
            UnitField(unit: "X", value: k.end.x, decimals: 1, suffix: "°") { v in editSkew("Skew") { k, _ in k.end.x = v } }
            UnitField(unit: "Y", value: k.end.y, decimals: 1, suffix: "°") { v in editSkew("Skew") { k, _ in k.end.y = v } }
        }
        .help("X slants its sides, so the bottom moves across; Y slants its top and bottom, so the right side moves down.")
    }

    private func editSkew(_ name: String, _ change: @escaping (inout SkewAction, LayerState) -> Void) {
        controller.editActions(name) { a in
            guard case .skew(var k) = a.spec, let state = controller.inheritedState(for: a) else { return }
            change(&k, state)
            a.spec = .skew(k)
        }
    }

    // MARK: Tilt

    @ViewBuilder private func tilt(_ t: TiltAction) -> some View {
        let from = inherited?.tilt ?? .none
        StackedRow(label: "From", accessory: { clearButton(t.initial != nil) { editTilt("Starting Value") { t, _ in t.initial = nil } } }) {
            OptionalField(unit: "X", value: t.initial?.x, placeholder: from.x, decimals: 1, suffix: "°") { v in
                editTilt("Starting Value") { t, s in t.initial = v.map { Tilt(x: $0, y: (t.initial ?? s.tilt).y, depth: t.end.depth) } }
            }
            OptionalField(unit: "Y", value: t.initial?.y, placeholder: from.y, decimals: 1, suffix: "°") { v in
                editTilt("Starting Value") { t, s in t.initial = v.map { Tilt(x: (t.initial ?? s.tilt).x, y: $0, depth: t.end.depth) } }
            }
        }
        .help("The tilt it starts at. Empty starts from the layer's tilt when the action begins.")
        StackedRow(label: t.mode == .to ? "To" : "By", menu: modeEntries(t.mode), swap: swap) {
            UnitField(unit: "X", value: t.end.x, decimals: 1, suffix: "°") { v in editTilt("Tilt") { t, _ in t.end.x = v } }
            UnitField(unit: "Y", value: t.end.y, decimals: 1, suffix: "°") { v in editTilt("Tilt") { t, _ in t.end.y = v } }
        }
        .help("X tips it back around a level line through its anchor, the top going away; Y turns it around an upright line, the right side going away. 180° shows its back.")
        StackedRow(label: "Depth") {
            UnitField(value: t.end.depth, decimals: 0, suffix: "px", accepts: { $0 > 1 }) { v in
                editTilt("Depth") { t, _ in
                    t.end.depth = v
                    t.initial?.depth = v
                }
            }
        }
        .help("How far away it is seen from. Nearer makes the perspective stronger.")
    }

    private func editTilt(_ name: String, _ change: @escaping (inout TiltAction, LayerState) -> Void) {
        controller.editActions(name) { a in
            guard case .tilt(var t) = a.spec, let state = controller.inheritedState(for: a) else { return }
            change(&t, state)
            a.spec = .tilt(t)
        }
    }

    // MARK: Opacity

    @ViewBuilder private func opacity(_ o: OpacityAction) -> some View {
        StackedRow(label: "From", accessory: { clearButton(o.initial != nil) { editOpacity("Starting Value") { $0.initial = nil } } }) {
            OptionalField(value: o.initial.map { $0 * 100 }, placeholder: (inherited?.opacity ?? 1) * 100,
                          suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                editOpacity("Starting Value") { $0.initial = v.map { $0 / 100 } }
            }
        }
        .help("The opacity it starts at. Set it to fade a layer in from nothing, before the action begins.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: o.end * 100, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                editOpacity("Opacity") { $0.end = v / 100 }
            }
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
        StackedRow(label: "From", accessory: { clearButton(r.initial != nil) { editResize("Starting Value") { r, _ in r.initial = nil } } }) {
            OptionalField(unit: "W", value: r.initial?.width, placeholder: from.width, accepts: { $0 >= 0 }) { v in
                editResize("Starting Value") { r, st in r.initial = v.map { Size2($0, (r.initial ?? st.size).height) } }
            }
            OptionalField(unit: "H", value: r.initial?.height, placeholder: from.height, accepts: { $0 >= 0 }) { v in
                editResize("Starting Value") { r, st in r.initial = v.map { Size2((r.initial ?? st.size).width, $0) } }
            }
        }
        .help("The size it starts at. Empty starts from the layer's size when the action begins.")
        StackedRow(label: "To", swap: swap, accessory: {
            IconButton(icon: r.isLinked ? .link : .unlink, help: r.isLinked ? "Unlink width and height" : "Keep width and height in proportion") {
                editResize("Link Size") { r, _ in r.isLinked.toggle() }
            }
        }) {
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
        .help("Hides or shows the layer at the action's start. A Show brings back a layer that was hidden or faded out.")
    }

    // MARK: Shared

    /// Swaps From and To, where the action has both.
    private var swap: (() -> Void)? {
        guard let inherited, ActionGeometry.swappingEnds(action, from: inherited) != nil else { return nil }
        return { controller.swapActionEnds() }
    }

    /// To ends at a fixed value; By changes the starting value by an
    /// amount. Chosen from the end row's name.
    private func modeEntries(_ mode: ActionMode) -> [MenuEntry] {
        ActionMode.allCases.map { new in
            .item(new == .to ? "To" : "By", checked: new == mode) {
                guard new != mode else { return }
                controller.editActions("Change Mode") { a in
                    guard let state = controller.inheritedState(for: a) else { return }
                    a = ActionGeometry.switchingMode(a, to: new, from: state)
                }
            }
        }
    }

    /// Empties the starting value, so it inherits again. In the button
    /// column on the From row.
    @ViewBuilder private func clearButton(_ visible: Bool, _ action: @escaping () -> Void) -> some View {
        if visible {
            IconButton(icon: .close, help: "Start from wherever the layer is instead", action: action)
        }
    }
}
