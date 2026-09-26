import SwiftUI
import MotionModel
import MotionEvaluation
import Theme

/// The values of Style and Blur actions: where each starts (empty picks up
/// whatever the layer has when the action begins) and where it ends.
struct StyleValueFields: View {
    let controller: EditorController
    let action: Action
    let inherited: LayerState?

    var body: some View {
        switch action.spec {
        case .color(let c): color(c)
        case .stroke(let s): stroke(s)
        case .trim(let t): trim(t)
        case .cornerRadius(let r): corners(r)
        case .shadow(let s): shadow(s)
        case .layerBlur(let b): layerBlur(b)
        case .backgroundBlur(let b): backgroundBlur(b)
        default: EmptyView()
        }
    }

    // MARK: Colour

    @ViewBuilder private func color(_ c: ColorAction) -> some View {
        let from = inherited?.fill ?? c.end
        optionalStart(isSet: c.initial != nil, preview: PaintSwatch(paint: from),
                      set: { editing("Starting Colour", Self.color { a, s in a.initial = s?.fill ?? a.end }) },
                      clear: { editing("Starting Colour", Self.color { a, _ in a.initial = nil }) }) {
            if let initial = c.initial {
                PaintControls(paint: initial, edit: callbacks("Starting Colour", Self.color) { $0.initial = $1 })
            }
        }
        .help("The colour it starts from. Empty starts from the layer's fill when the action begins.")
        sectionLabel("To")
        PaintControls(paint: c.end, edit: callbacks("Colour", Self.color) { $0.end = $1 })
    }

    // MARK: Stroke

    @ViewBuilder private func stroke(_ s: StrokeAction) -> some View {
        let from = inherited?.stroke ?? s.end
        LabeledRow(label: "From") {
            OptionalField(unit: "W", value: s.initial?.width, placeholder: from.width, decimals: 1, suffix: "px",
                          accepts: { $0 >= 0 }) { v in
                editing("Starting Stroke", Self.stroke { a, st in
                    a.initial = v.map { StrokeLook(width: $0, paint: (a.initial ?? st?.stroke ?? a.end).paint) }
                })
            }
            clearButton(s.initial != nil) { editing("Starting Stroke", Self.stroke { a, _ in a.initial = nil }) }
        }
        .help("The width it starts at. Empty starts from the layer's stroke when the action begins.")
        if let initial = s.initial {
            PaintControls(paint: initial.paint, title: "Stroke",
                          edit: callbacks("Starting Stroke", Self.stroke) { a, p in a.initial?.paint = p })
        }
        LabeledRow(label: "To") {
            UnitField(unit: "W", value: s.end.width, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                editing("Stroke", Self.stroke { a, _ in a.end.width = v })
            }
            spacer
        }
        PaintControls(paint: s.end.paint, title: "Stroke", edit: callbacks("Stroke", Self.stroke) { $0.end.paint = $1 })
    }

    // MARK: Trim

    @ViewBuilder private func trim(_ t: TrimAction) -> some View {
        let from = inherited?.trim ?? .whole
        LabeledRow(label: "From") {
            OptionalField(value: t.initial.map { $0.start * 100 }, placeholder: from.start * 100,
                          decimals: 1, suffix: "%", accepts: Self.percent) { v in
                editing("Starting Trim", Self.trim { a, st in
                    a.initial = v.map { TrimRange(start: $0 / 100, end: (a.initial ?? st?.trim ?? .whole).end) }
                })
            }
            OptionalField(value: t.initial.map { $0.end * 100 }, placeholder: from.end * 100,
                          decimals: 1, suffix: "%", accepts: Self.percent) { v in
                editing("Starting Trim", Self.trim { a, st in
                    a.initial = v.map { TrimRange(start: (a.initial ?? st?.trim ?? .whole).start, end: $0 / 100) }
                })
            }
            clearButton(t.initial != nil) { editing("Starting Trim", Self.trim { a, _ in a.initial = nil }) }
        }
        // No S and E letters: "100 %" only just fits beside the button.
        .help("How much of the stroke is drawn when it starts: from the first number to the second, along the path. Set both to 0% to draw it on from nothing.")
        LabeledRow(label: "To") {
            UnitField(value: t.end.start * 100, decimals: 1, suffix: "%", accepts: Self.percent) { v in
                editing("Trim", Self.trim { a, _ in a.end.start = v / 100 })
            }
            UnitField(value: t.end.end * 100, decimals: 1, suffix: "%", accepts: Self.percent) { v in
                editing("Trim", Self.trim { a, _ in a.end.end = v / 100 })
            }
            spacer
        }
        .help("How much is drawn when it ends, from the first number to the second. 0% to 100% is the whole stroke.")
    }

    // MARK: Corner radius

    @ViewBuilder private func corners(_ r: CornerRadiusAction) -> some View {
        let from = inherited?.cornerRadii ?? .zero
        if r.isLinked {
            LabeledRow(label: "From") {
                OptionalField(unit: "R", value: r.initial?.topLeft, placeholder: from.topLeft, accepts: { $0 >= 0 }) { v in
                    editing("Starting Corners", Self.corners { a, _ in a.initial = v.map { CornerRadii(all: $0) } })
                }
                clearButton(r.initial != nil) { editing("Starting Corners", Self.corners { a, _ in a.initial = nil }) }
            }
            .help("The radius it starts at. Empty starts from the layer's corners when the action begins.")
            LabeledRow(label: "To") {
                UnitField(unit: "R", value: r.end.topLeft, accepts: { $0 >= 0 }) { v in
                    editing("Corner Radius", Self.corners { a, _ in a.end = CornerRadii(all: v) })
                }
                linkButton(r)
            }
        } else {
            sectionLabel("From") {
                clearButton(r.initial != nil) { editing("Starting Corners", Self.corners { a, _ in a.initial = nil }) }
            }
            cornerGrid { corner in
                OptionalField(unit: corner.unit, value: r.initial?[keyPath: corner.path], placeholder: from[keyPath: corner.path],
                              accepts: { $0 >= 0 }) { v in
                    editing("Starting Corners", Self.corners { a, st in
                        guard let v else { a.initial = nil; return }
                        var radii = a.initial ?? st?.cornerRadii ?? .zero
                        radii[keyPath: corner.path] = v
                        a.initial = radii
                    })
                }
            }
            .help("The corners it starts at, clockwise from the top left. Empty starts from the layer's corners.")
            sectionLabel("To") { linkButton(r) }
            cornerGrid { corner in
                UnitField(unit: corner.unit, value: r.end[keyPath: corner.path], accepts: { $0 >= 0 }) { v in
                    editing("Corner Radius", Self.corners { a, _ in a.end[keyPath: corner.path] = v })
                }
            }
        }
    }

    private struct Corner: Identifiable {
        let unit: String
        let path: WritableKeyPath<CornerRadii, Double>
        var id: String { unit }
    }

    /// Four fields in the corners' own places: top left and right, then
    /// bottom left and right.
    private func cornerGrid<Field: View>(@ViewBuilder _ field: @escaping (Corner) -> Field) -> some View {
        let rows = [[Corner(unit: "TL", path: \.topLeft), Corner(unit: "TR", path: \.topRight)],
                    [Corner(unit: "BL", path: \.bottomLeft), Corner(unit: "BR", path: \.bottomRight)]]
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                HStack(spacing: 8) { ForEach(rows[i]) { field($0) } }
            }
        }
    }

    private func linkButton(_ r: CornerRadiusAction) -> some View {
        IconButton(icon: r.isLinked ? .link : .unlink, help: r.isLinked ? "Set each corner on its own" : "One radius for every corner") {
            editing("Link Corners", Self.corners { a, _ in
                a.isLinked.toggle()
                if a.isLinked {
                    a.end = CornerRadii(all: a.end.topLeft)
                    a.initial = a.initial.map { CornerRadii(all: $0.topLeft) }
                }
            })
        }
    }

    // MARK: Shadow

    @ViewBuilder private func shadow(_ s: ShadowAction) -> some View {
        let from = inherited?.shadow ?? DropShadow.noShadow
        optionalStart(isSet: s.initial != nil, preview: PaintSwatch(paint: .solid(Self.seen(from))),
                      set: { editing("Starting Shadow", Self.shadow { a, st in
                          // From no shadow, it starts in the end's colour at 0%,
                          // so only the opacity needs raising.
                          let from = st?.shadow ?? DropShadow.noShadow
                          a.initial = from.opacity > 0 ? from : DropShadow(color: a.end.color, offset: .zero, blur: 0, opacity: 0)
                      }) },
                      clear: { editing("Starting Shadow", Self.shadow { a, _ in a.initial = nil }) }) {
            if let initial = s.initial {
                ShadowControls(shadow: initial, edit: callbacks("Starting Shadow", Self.shadow) { $0.initial = $1 })
            }
        }
        .help("The shadow it starts from. Empty starts from the layer's shadow when the action begins, or from none.")
        sectionLabel("To")
        ShadowControls(shadow: s.end, edit: callbacks("Shadow", Self.shadow) { $0.end = $1 })
    }

    /// The shadow's colour as it shows, with its opacity folded in.
    private static func seen(_ shadow: DropShadow) -> RGBA {
        var c = shadow.color
        c.a *= shadow.opacity
        return c
    }

    // MARK: Blurs

    @ViewBuilder private func layerBlur(_ b: LayerBlurAction) -> some View {
        LabeledRow(label: "From") {
            OptionalField(unit: "Blur", value: b.initial, placeholder: inherited?.layerBlur ?? 0, decimals: 1,
                          accepts: { $0 >= 0 }) { v in
                editing("Starting Blur", Self.layerBlur { a, _ in a.initial = v })
            }
            clearButton(b.initial != nil) { editing("Starting Blur", Self.layerBlur { a, _ in a.initial = nil }) }
        }
        .help("The blur it starts at. Empty starts from the layer's blur when the action begins, or from none.")
        LabeledRow(label: "To") {
            UnitField(unit: "Blur", value: b.end, decimals: 1, accepts: { $0 >= 0 }) { v in
                editing("Layer Blur", Self.layerBlur { a, _ in a.end = v })
            }
            spacer
        }
    }

    @ViewBuilder private func backgroundBlur(_ b: BackgroundBlurAction) -> some View {
        let from = inherited?.backgroundBlur ?? BackgroundBlur.noBlur
        LabeledRow(label: "From") {
            OptionalField(value: b.initial?.radius, placeholder: from.radius, decimals: 1, suffix: "px",
                          accepts: { $0 >= 0 }) { v in
                editing("Starting Blur", Self.backgroundBlur { a, st in
                    a.initial = v.map { BackgroundBlur(radius: $0, blend: (a.initial ?? st?.backgroundBlur ?? BackgroundBlur.noBlur).blend) }
                })
            }
            OptionalField(value: b.initial.map { $0.blend * 100 }, placeholder: from.blend * 100, suffix: "%",
                          accepts: Self.percent) { v in
                editing("Starting Blur", Self.backgroundBlur { a, st in
                    a.initial = v.map { BackgroundBlur(radius: (a.initial ?? st?.backgroundBlur ?? BackgroundBlur.noBlur).radius, blend: $0 / 100) }
                })
            }
            clearButton(b.initial != nil) { editing("Starting Blur", Self.backgroundBlur { a, _ in a.initial = nil }) }
        }
        // Blur in px, then blend in %: no room for their names beside the button.
        .help("The blur (px) and blend (%) it starts at. Empty starts from the layer's background blur, or from none.")
        LabeledRow(label: "To") {
            UnitField(value: b.end.radius, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                editing("Background Blur", Self.backgroundBlur { a, _ in a.end.radius = v })
            }
            UnitField(value: b.end.blend * 100, suffix: "%", accepts: Self.percent) { v in
                editing("Background Blur", Self.backgroundBlur { a, _ in a.end.blend = v / 100 })
            }
            .help("Blend: how much of the blurred background shows over the sharp one.")
            spacer
        }
    }

    // MARK: Editing

    /// A change to one kind's values, given what the action would inherit.
    typealias Change<T> = (inout T, LayerState?) -> Void

    private static func color(_ change: @escaping Change<ColorAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .color(var v) = a.spec { change(&v, st); a.spec = .color(v) } }
    }
    private static func stroke(_ change: @escaping Change<StrokeAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .stroke(var v) = a.spec { change(&v, st); a.spec = .stroke(v) } }
    }
    private static func trim(_ change: @escaping Change<TrimAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .trim(var v) = a.spec { change(&v, st); a.spec = .trim(v) } }
    }
    private static func corners(_ change: @escaping Change<CornerRadiusAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .cornerRadius(var v) = a.spec { change(&v, st); a.spec = .cornerRadius(v) } }
    }
    private static func shadow(_ change: @escaping Change<ShadowAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .shadow(var v) = a.spec { change(&v, st); a.spec = .shadow(v) } }
    }
    private static func layerBlur(_ change: @escaping Change<LayerBlurAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .layerBlur(var v) = a.spec { change(&v, st); a.spec = .layerBlur(v) } }
    }
    private static func backgroundBlur(_ change: @escaping Change<BackgroundBlurAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .backgroundBlur(var v) = a.spec { change(&v, st); a.spec = .backgroundBlur(v) } }
    }

    /// Applies `change` to every selected action as one undo step.
    private func editing(_ name: String, _ change: @escaping (inout Action, LayerState?) -> Void) {
        controller.editActions(name) { a in change(&a, controller.inheritedState(for: a)) }
    }

    /// Typed changes as single steps; picker drags as live changes that undo
    /// together.
    private func callbacks<Kind, Value>(_ name: String,
                                        _ wrap: @escaping (@escaping Change<Kind>) -> (inout Action, LayerState?) -> Void,
                                        _ set: @escaping (inout Kind, Value) -> Void) -> EditCallbacks<Value> {
        EditCallbacks(
            commit: { value in editing(name, wrap { k, _ in set(&k, value) }) },
            live: { value in controller.updateActions { a in wrap { k, _ in set(&k, value) }(&a, nil) } },
            begin: { controller.begin(name) },
            end: { controller.end() })
    }

    // MARK: Pieces

    private static func percent(_ v: Double) -> Bool { v >= 0 && v <= 100 }

    /// Keeps a row's fields the width of the rows with a button at the end.
    private var spacer: some View { Color.clear.frame(width: Theme.control) }

    private func sectionLabel(_ title: String) -> some View {
        sectionLabel(title) { EmptyView() }
    }

    private func sectionLabel<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            accessory()
        }
        .frame(height: Theme.panelRow)
    }

    /// A starting value too big for one field. Empty, it shows what it
    /// would start from, with a button to set it there and change it; set,
    /// its controls follow, with a button to empty it again.
    @ViewBuilder private func optionalStart<Preview: View, Content: View>(
        isSet: Bool, preview: Preview, set: @escaping () -> Void, clear: @escaping () -> Void,
        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if isSet {
                sectionLabel("From") {
                    IconButton(icon: .close, help: "Start from wherever the layer is instead", action: clear)
                }
                content()
            } else {
                LabeledRow(label: "From") {
                    preview
                    Text("Current")
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                    IconButton(icon: .plus, help: "Set where it starts", action: set)
                }
            }
        }
    }

    @ViewBuilder private func clearButton(_ visible: Bool, _ action: @escaping () -> Void) -> some View {
        if visible {
            IconButton(icon: .close, help: "Start from wherever the layer is instead", action: action)
        } else {
            spacer
        }
    }
}
