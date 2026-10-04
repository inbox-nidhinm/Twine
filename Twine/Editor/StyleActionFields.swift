import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// The values of Style, Blur, Text and Shape actions: where each starts
/// (empty picks up whatever the layer has when the action begins) and where
/// it ends.
struct StyleValueFields: View {
    let controller: EditorController
    let action: Action
    let inherited: LayerState?

    var body: some View {
        switch action.spec {
        case .color(let c): color(c)
        case .stroke(let s): stroke(s)
        case .trim(let t): trim(t)
        case .dash(let d): dash(d)
        case .cornerRadius(let r): corners(r)
        case .shadow(let s): shadow(s, inner: false)
        case .innerShadow(let s): shadow(s, inner: true)
        case .layerBlur(let b): layerBlur(b)
        case .backgroundBlur(let b): backgroundBlur(b)
        case .letterSpacing(let v): letterSpacing(v)
        case .lineHeight(let v): lineHeight(v)
        case .counter(let c): counter(c)
        case .changeText(let c): changeText(c)
        case .arc(let a): arc(a)
        case .star(let s): star(s)
        case .path(let p): path(p)
        case .play(let p): play(p)
        case .volume(let v): volume(v)
        default: EmptyView()
        }
    }

    private var isText: Bool { inherited?.text != nil }

    // MARK: Colour

    @ViewBuilder private func color(_ c: ColorAction) -> some View {
        let from = inherited?.fill ?? c.end
        optionalStart(isSet: c.initial != nil, preview: PaintSwatch(paint: from),
                      set: { editing("Starting Colour", Self.color { a, s in a.initial = s?.fill ?? a.end }) },
                      clear: { editing("Starting Colour", Self.color { a, _ in a.initial = nil }) }) {
            if let initial = c.initial {
                PaintControls(paint: initial, allowsGradients: !isText,
                              edit: callbacks("Starting Colour", Self.color) { $0.initial = $1 })
            }
        }
        .help("The colour it starts from. Empty starts from the layer's fill when the action begins.")
        sectionLabel("To", swap: swap)
        PaintControls(paint: c.end, allowsGradients: !isText, edit: callbacks("Colour", Self.color) { $0.end = $1 })
    }

    // MARK: Stroke

    @ViewBuilder private func stroke(_ s: StrokeAction) -> some View {
        let from = inherited?.stroke ?? s.end
        StackedRow(label: "From", accessory: { clearButton(s.initial != nil) { editing("Starting Stroke", Self.stroke { a, _ in a.initial = nil }) } }) {
            OptionalField(unit: "W", value: s.initial?.width, placeholder: from.width, decimals: 1, suffix: "px",
                          accepts: { $0 >= 0 }) { v in
                editing("Starting Stroke", Self.stroke { a, st in
                    a.initial = v.map { StrokeLook(width: $0, paint: (a.initial ?? st?.stroke ?? a.end).paint) }
                })
            }
        }
        .help("The width it starts at. Empty starts from the layer's stroke when the action begins.")
        if let initial = s.initial {
            PaintControls(paint: initial.paint, title: "Stroke", allowsGradients: !isText,
                          edit: callbacks("Starting Stroke", Self.stroke) { a, p in a.initial?.paint = p })
        }
        StackedRow(label: "To", swap: swap) {
            UnitField(unit: "W", value: s.end.width, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                editing("Stroke", Self.stroke { a, _ in a.end.width = v })
            }
        }
        PaintControls(paint: s.end.paint, title: "Stroke", allowsGradients: !isText, edit: callbacks("Stroke", Self.stroke) { $0.end.paint = $1 })
    }

    // MARK: Trim

    @ViewBuilder private func trim(_ t: TrimAction) -> some View {
        let from = inherited?.trim ?? .whole
        MenuRow(label: "Draws", value: t.end.direction.title, entries: {
            TrimDirection.allCases.map { d in
                .item(d.title, checked: d == t.end.direction) {
                    editing("Trim Direction", Self.trim { a, _ in
                        a.end.direction = d
                        a.initial?.direction = d
                    })
                }
            }
        })
        .help("Which way the line draws: from its start, from its end, from both ends to meet in the middle, or from the middle out")
        StackedRow(label: "From", accessory: { clearButton(t.initial != nil) { editing("Starting Trim", Self.trim { a, _ in a.initial = nil }) } }) {
            OptionalField(value: t.initial.map { $0.amount * 100 }, placeholder: from.amount * 100,
                          decimals: 1, suffix: "%", accepts: Self.percent) { v in
                editing("Starting Trim", Self.trim { a, _ in
                    a.initial = v.map { TrimRange(direction: a.end.direction, amount: $0 / 100) }
                })
            }
        }
        .help("How much of the line is drawn when it starts. 0% draws it on from nothing.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: t.end.amount * 100, decimals: 1, suffix: "%", accepts: Self.percent) { v in
                editing("Trim", Self.trim { a, _ in a.end.amount = v / 100 })
            }
        }
        .help("How much of the line is drawn when it ends. 100% is all of it.")
    }

    // MARK: Dashes

    @ViewBuilder private func dash(_ d: DashAction) -> some View {
        LabeledRow(label: "Speed") {
            UnitField(value: d.speed, decimals: 0, suffix: "px/s", accepts: { $0 >= 0 && $0 <= 100_000 }) { v in
                editing("Dash Speed", Self.dash { a, _ in a.speed = v })
            }
        }
        .help("How far the dashes travel each second")
        ToggleRow(label: "Follow trim", isOn: d.followsTrim) {
            editing(d.followsTrim ? "Stop Following Trim" : "Follow Trim", Self.dash { a, _ in a.followsTrim.toggle() })
        }
        .help("The dashes travel the way the stroke's trim draws it, each part towards its growing end")
        if !d.followsTrim {
            LabeledRow(label: "Direction") {
                SegmentRow(selection: d.direction, options: DashDirection.allCases,
                           title: { $0 == .forward ? "Towards the end" : "Towards the start" },
                           icon: { $0 == .forward ? .arrowRight : .arrowLeft }) { way in
                    editing("Dash Direction", Self.dash { a, _ in a.direction = way })
                }
            }
            .help("Which way along the path the dashes travel")
        }
    }

    // MARK: Corner radius

    @ViewBuilder private func corners(_ r: CornerRadiusAction) -> some View {
        let from = inherited?.cornerRadii ?? .zero
        if r.isLinked {
            StackedRow(label: "From", accessory: { clearButton(r.initial != nil) { editing("Starting Corners", Self.corners { a, _ in a.initial = nil }) } }) {
                OptionalField(unit: "R", value: r.initial?.topLeft, placeholder: from.topLeft, accepts: { $0 >= 0 }) { v in
                    editing("Starting Corners", Self.corners { a, _ in a.initial = v.map { CornerRadii(all: $0) } })
                }
            }
            .help("The radius it starts at. Empty starts from the layer's corners when the action begins.")
            StackedRow(label: "To", swap: swap, accessory: { linkButton(r) }) {
                UnitField(unit: "R", value: r.end.topLeft, accepts: { $0 >= 0 }) { v in
                    editing("Corner Radius", Self.corners { a, _ in a.end = CornerRadii(all: v) })
                }
            }
        } else {
            sectionLabel("From") {
                clearButton(r.initial != nil) { editing("Starting Corners", Self.corners { a, _ in a.initial = nil }) }
            }
            cornerGrid { corner in
                OptionalField(icon: corner.icon, value: r.initial?[keyPath: corner.path], placeholder: from[keyPath: corner.path],
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
            sectionLabel("To", swap: swap) { linkButton(r) }
            cornerGrid { corner in
                UnitField(icon: corner.icon, value: r.end[keyPath: corner.path], accepts: { $0 >= 0 }) { v in
                    editing("Corner Radius", Self.corners { a, _ in a.end[keyPath: corner.path] = v })
                }
            }
        }
    }

    private struct Corner: Identifiable {
        let icon: Icon
        let path: WritableKeyPath<CornerRadii, Double>
        var id: Icon { icon }
    }

    /// Four fields in the corners' own places: top left and right, then
    /// bottom left and right.
    private func cornerGrid<Field: View>(@ViewBuilder _ field: @escaping (Corner) -> Field) -> some View {
        let rows = [[Corner(icon: .cornerTopLeft, path: \.topLeft), Corner(icon: .cornerTopRight, path: \.topRight)],
                    [Corner(icon: .cornerBottomLeft, path: \.bottomLeft), Corner(icon: .cornerBottomRight, path: \.bottomRight)]]
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

    /// A Shadow or an Inner Shadow action: the same values, on the layer's
    /// first drop shadow or its first inner shadow.
    @ViewBuilder private func shadow(_ s: ShadowAction, inner: Bool) -> some View {
        let name = inner ? "Inner Shadow" : "Shadow"
        let designed: (LayerState?) -> DropShadow = { inner ? $0?.innerShadow.shadow ?? .noShadow : $0?.shadow ?? .noShadow }
        let from = designed(inherited)
        optionalStart(isSet: s.initial != nil, preview: PaintSwatch(paint: .solid(Self.seen(from))),
                      set: { editing("Starting \(name)", Self.shadow { a, st in
                          // From no shadow, it starts in the end's colour at 0%,
                          // so only the opacity needs raising.
                          let from = designed(st)
                          a.initial = from.opacity > 0 ? from : DropShadow(color: a.end.color, offset: .zero, blur: 0, opacity: 0)
                      }) },
                      clear: { editing("Starting \(name)", Self.shadow { a, _ in a.initial = nil }) }) {
            if let initial = s.initial {
                ShadowControls(shadow: initial, edit: callbacks("Starting \(name)", Self.shadow) { $0.initial = $1 })
            }
        }
        .help(inner ? "The inner shadow it starts from. Empty starts from the layer's inner shadow when the action begins, or from none."
                    : "The shadow it starts from. Empty starts from the layer's shadow when the action begins, or from none.")
        sectionLabel("To", swap: swap)
        ShadowControls(shadow: s.end, edit: callbacks(name, Self.shadow) { $0.end = $1 })
    }

    /// The shadow's colour as it shows, with its opacity folded in.
    private static func seen(_ shadow: DropShadow) -> RGBA {
        var c = shadow.color
        c.a *= shadow.opacity
        return c
    }

    // MARK: Blurs

    @ViewBuilder private func layerBlur(_ b: LayerBlurAction) -> some View {
        StackedRow(label: "From", accessory: { clearButton(b.initial != nil) { editing("Starting Blur", Self.layerBlur { a, _ in a.initial = nil }) } }) {
            OptionalField(unit: "Blur", value: b.initial, placeholder: inherited?.layerBlur ?? 0, decimals: 1,
                          accepts: { $0 >= 0 }) { v in
                editing("Starting Blur", Self.layerBlur { a, _ in a.initial = v })
            }
        }
        .help("The blur it starts at. Empty starts from the layer's blur when the action begins, or from none.")
        StackedRow(label: "To", swap: swap) {
            UnitField(unit: "Blur", value: b.end, decimals: 1, accepts: { $0 >= 0 }) { v in
                editing("Layer Blur", Self.layerBlur { a, _ in a.end = v })
            }
        }
    }

    @ViewBuilder private func backgroundBlur(_ b: BackgroundBlurAction) -> some View {
        let from = inherited?.backgroundBlur ?? BackgroundBlur.noBlur
        StackedRow(label: "From", accessory: { clearButton(b.initial != nil) { editing("Starting Blur", Self.backgroundBlur { a, _ in a.initial = nil }) } }) {
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
        }
        // Blur in px, then blend in %: no room for their names beside the button.
        .help("The blur (px) and blend (%) it starts at. Empty starts from the layer's background blur, or from none.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: b.end.radius, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                editing("Background Blur", Self.backgroundBlur { a, _ in a.end.radius = v })
            }
            UnitField(value: b.end.blend * 100, suffix: "%", accepts: Self.percent) { v in
                editing("Background Blur", Self.backgroundBlur { a, _ in a.end.blend = v / 100 })
            }
            .help("Blend: how much of the blurred background shows over the sharp one.")
        }
    }

    // MARK: Text

    @ViewBuilder private func letterSpacing(_ v: LetterSpacingAction) -> some View {
        StackedRow(label: "From", accessory: { clearButton(v.initial != nil) { editing("Starting Spacing", Self.letterSpacing { a, _ in a.initial = nil }) } }) {
            OptionalField(value: v.initial, placeholder: inherited?.letterSpacing ?? 0, decimals: 1, suffix: "px") { x in
                editing("Starting Spacing", Self.letterSpacing { a, _ in a.initial = x })
            }
        }
        .help("The letter spacing it starts at. Empty starts from the text's own.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: v.end, decimals: 1, suffix: "px") { x in editing("Letter Spacing", Self.letterSpacing { a, _ in a.end = x }) }
        }
    }

    @ViewBuilder private func lineHeight(_ v: LineHeightAction) -> some View {
        StackedRow(label: "From", accessory: { clearButton(v.initial != nil) { editing("Starting Line Height", Self.lineHeight { a, _ in a.initial = nil }) } }) {
            OptionalField(value: v.initial, placeholder: inherited?.lineHeight ?? 0, decimals: 1, suffix: "px",
                          accepts: { $0 > 0 }) { x in
                editing("Starting Line Height", Self.lineHeight { a, _ in a.initial = x })
            }
        }
        .help("The line height it starts at, baseline to baseline. Empty starts from the text's own.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: v.end, decimals: 1, suffix: "px", accepts: { $0 > 0 }) { x in
                editing("Line Height", Self.lineHeight { a, _ in a.end = x })
            }
        }
    }

    @ViewBuilder private func counter(_ c: CounterAction) -> some View {
        let found = NumberFormat.read(inherited?.text?.text ?? "")?.value ?? 0
        StackedRow(label: "From", accessory: { clearButton(c.from != nil) { editing("Counter", Self.counter { a, _ in a.from = nil }) } }) {
            OptionalField(value: c.from, placeholder: found, decimals: 4) { x in
                editing("Counter", Self.counter { a, _ in a.from = x })
            }
        }
        .help("The number it counts from. Empty starts from the number in the text, or 0. Set, it shows from the start of the animation.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: c.to, decimals: 4) { x in editing("Counter", Self.counter { a, _ in a.to = x }) }
        }
        StackedRow(label: "Step") {
            UnitField(value: c.step, decimals: 4, accepts: { $0 > 0 }) { x in editing("Counter", Self.counter { a, _ in a.step = x }) }
        }
        .help("How much each change adds. The count keeps the text's own look: its symbols, decimals, separators and zeros.")
        SegmentRow(selection: c.transition, options: [.none, .fade, .slide], title: Self.transitionTitle) { t in
            editing("Counter", Self.counter { a, _ in a.transition = t })
        }
        .help("How each number gives way to the next. Fade and slide roll smoothly from one to the next.")
    }

    @ViewBuilder private func changeText(_ c: ChangeTextAction) -> some View {
        sectionLabel("To", swap: swap)
        WordsField(text: c.text) { new in editing("Change Text", Self.changeText { a, _ in a.text = new }) }
            .help("The new words. Option-Return starts a new line.")
        sectionLabel("Out")
        SegmentRow(selection: c.transitionOut, options: TextTransition.allCases, title: Self.transitionTitle) { t in
            editing("Change Text", Self.changeText { a, _ in a.transitionOut = t })
        }
        .help("How the old words leave")
        sectionLabel("In")
        SegmentRow(selection: c.transitionIn, options: TextTransition.allCases, title: Self.transitionTitle) { t in
            editing("Change Text", Self.changeText { a, _ in a.transitionIn = t })
        }
        .help("How the new words arrive")
        ToggleRow(label: "Overlap", isOn: c.overlaps) {
            editing("Change Text", Self.changeText { a, _ in a.overlaps.toggle() })
        }
        .help("Runs out and in at the same time, instead of one after the other.")
    }

    static func transitionTitle(_ t: TextTransition) -> String {
        switch t {
        case .none: return "None"
        case .fade: return "Fade"
        case .slide: return "Slide"
        case .scale: return "Scale"
        }
    }

    // MARK: Shape

    @ViewBuilder private func arc(_ v: ArcAction) -> some View {
        let from = inherited?.arc ?? .full
        sectionLabel("From") {
            clearButton(v.initial != nil) { editing("Starting Arc", Self.arc { a, _ in a.initial = nil }) }
        }
        HStack(spacing: 8) {
            OptionalField(unit: "Start", value: v.initial?.start, placeholder: from.start, decimals: 1, suffix: "°") { x in
                editing("Starting Arc", Self.arc { a, st in
                    guard let x else { a.initial = nil; return }
                    let base = a.initial ?? st?.arc ?? .full
                    a.initial = EllipseArc(start: x, end: x + base.end - base.start, innerRadius: base.innerRadius)
                })
            }
            OptionalField(unit: "Sweep", value: v.initial.map { $0.end - $0.start }, placeholder: from.end - from.start,
                          decimals: 1, suffix: "°") { x in
                editing("Starting Arc", Self.arc { a, st in
                    guard let x else { a.initial = nil; return }
                    let base = a.initial ?? st?.arc ?? .full
                    a.initial = EllipseArc(start: base.start, end: base.start + x, innerRadius: base.innerRadius)
                })
            }
        }
        OptionalField(unit: "Ratio", value: v.initial.map { $0.innerRadius * 100 }, placeholder: from.innerRadius * 100,
                      decimals: 1, suffix: "%", accepts: { $0 >= 0 && $0 < 100 }) { x in
            editing("Starting Arc", Self.arc { a, st in
                guard let x else { a.initial = nil; return }
                var base = a.initial ?? st?.arc ?? .full
                base.innerRadius = x / 100
                a.initial = base
            })
        }
        .help("The slice it starts as. Empty starts from the ellipse's own.")
        sectionLabel("To", swap: swap)
        HStack(spacing: 8) {
            UnitField(unit: "Start", value: v.end.start, decimals: 1, suffix: "°") { x in
                editing("Arc", Self.arc { a, _ in
                    let sweep = a.end.end - a.end.start
                    a.end.start = x
                    a.end.end = x + sweep
                })
            }
            UnitField(unit: "Sweep", value: v.end.end - v.end.start, decimals: 1, suffix: "°") { x in
                editing("Arc", Self.arc { a, _ in a.end.end = a.end.start + x })
            }
        }
        .help("Where the slice ends up: its start, in degrees clockwise from three o'clock, and how far round it goes.")
        UnitField(unit: "Ratio", value: v.end.innerRadius * 100, decimals: 1, suffix: "%", accepts: { $0 >= 0 && $0 < 100 }) { x in
            editing("Arc", Self.arc { a, _ in a.end.innerRadius = x / 100 })
        }
        .help("The hole in the middle, as a share of the ellipse")
    }

    /// The end shape is set on the canvas, point by point; here it can go
    /// back to the shape it starts from.
    @ViewBuilder private func path(_ v: PathAction) -> some View {
        let count = v.end.subpaths.reduce(0) { $0 + $1.points.count }
        StackedRow(label: "To", swap: swap, accessory: {
            IconButton(icon: .close, help: "Put the end back to the shape it starts from") {
                editing("Reset Path", Self.path { a, st in
                    if let from = a.initial ?? st?.path { a.end = from }
                })
            }
        }) {
            Text(count == 1 ? "1 point" : "\(count) points")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func star(_ v: StarAction) -> some View {
        let from = inherited?.star ?? v.end
        sectionLabel("From") {
            clearButton(v.initial != nil) { editing("Starting Star", Self.star { a, _ in a.initial = nil }) }
        }
        HStack(spacing: 8) {
            OptionalField(unit: "Points", value: v.initial.map { Double($0.points) }, placeholder: Double(from.points),
                          accepts: { $0 >= 3 && $0 <= 60 }) { x in
                editing("Starting Star", Self.star { a, st in
                    guard let x else { a.initial = nil; return }
                    var base = a.initial ?? st?.star ?? a.end
                    base.points = Int(x.rounded())
                    a.initial = base
                })
            }
            OptionalField(unit: "Inner", value: v.initial.map { $0.innerRadius * 100 }, placeholder: from.innerRadius * 100,
                          decimals: 1, suffix: "%", accepts: { $0 >= 0 }) { x in
                editing("Starting Star", Self.star { a, st in
                    guard let x else { a.initial = nil; return }
                    var base = a.initial ?? st?.star ?? a.end
                    base.innerRadius = x / 100
                    a.initial = base
                })
            }
        }
        OptionalField(unit: "Radius", value: v.initial?.cornerRadius, placeholder: from.cornerRadius, decimals: 1,
                      accepts: { $0 >= 0 }) { x in
            editing("Starting Star", Self.star { a, st in
                guard let x else { a.initial = nil; return }
                var base = a.initial ?? st?.star ?? a.end
                base.cornerRadius = x
                a.initial = base
            })
        }
        .help("The star it starts as. Empty starts from the star's own shape.")
        sectionLabel("To", swap: swap)
        HStack(spacing: 8) {
            UnitField(unit: "Points", value: Double(v.end.points), accepts: { $0 >= 3 && $0 <= 60 }) { x in
                editing("Star", Self.star { a, _ in a.end.points = Int(x.rounded()) })
            }
            .help("Points change a whole point at a time.")
            UnitField(unit: "Inner", value: v.end.innerRadius * 100, decimals: 1, suffix: "%", accepts: { $0 >= 0 }) { x in
                editing("Star", Self.star { a, _ in a.end.innerRadius = x / 100 })
            }
            .help("How far in the inner points sit, as a share of the outer ones")
        }
        UnitField(unit: "Radius", value: v.end.cornerRadius, decimals: 1, accepts: { $0 >= 0 }) { x in
            editing("Star", Self.star { a, _ in a.end.cornerRadius = x })
        }
        .help("Rounds every point, in pixels")
    }

    // MARK: Media

    @ViewBuilder private func play(_ p: PlayAction) -> some View {
        let length = controller.asset(ofLayer: action.targetLayerID)?.duration
        StackedRow(label: "Trim") {
            UnitField(value: p.trimStart, decimals: 2, suffix: "s", accepts: { v in v >= 0 && (length.map { v < $0 } ?? true) }) { v in
                controller.editActions("Trim") { a in
                    guard case .play(var play) = a.spec else { return }
                    play.trimStart = v
                    // Never past the end of the file.
                    if let length { a.duration = min(a.duration, max(controller.frameRate.snapped(length - v), controller.frameRate.frameDuration)) }
                    a.spec = .play(play)
                }
            }
        }
        .help("How far into the file it starts playing. Dragging the bar's left end on the timeline trims it too.")
    }

    /// A fade, in percent of the file's own level, up to 100%.
    @ViewBuilder private func volume(_ v: VolumeAction) -> some View {
        StackedRow(label: "From", accessory: { clearButton(v.initial != nil) { editing("Starting Volume", Self.volume { a, _ in a.initial = nil }) } }) {
            OptionalField(value: v.initial.map { $0 * 100 }, placeholder: (inherited?.volume ?? 1) * 100,
                          suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { x in
                editing("Starting Volume", Self.volume { a, _ in a.initial = x.map { $0 / 100 } })
            }
        }
        .help("The level it starts at. Set it to 0% to fade a sound in from nothing, before the action begins.")
        StackedRow(label: "To", swap: swap) {
            UnitField(value: v.end * 100, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { x in
                editing("Volume", Self.volume { a, _ in a.end = x / 100 })
            }
        }
        .help("The level it ends at: 100% is the file's own")
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
    private static func dash(_ change: @escaping Change<DashAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .dash(var v) = a.spec { change(&v, st); a.spec = .dash(v) } }
    }
    private static func corners(_ change: @escaping Change<CornerRadiusAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .cornerRadius(var v) = a.spec { change(&v, st); a.spec = .cornerRadius(v) } }
    }
    private static func shadow(_ change: @escaping Change<ShadowAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in
            switch a.spec {
            case .shadow(var v): change(&v, st); a.spec = .shadow(v)
            case .innerShadow(var v): change(&v, st); a.spec = .innerShadow(v)
            default: break
            }
        }
    }
    private static func layerBlur(_ change: @escaping Change<LayerBlurAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .layerBlur(var v) = a.spec { change(&v, st); a.spec = .layerBlur(v) } }
    }
    private static func backgroundBlur(_ change: @escaping Change<BackgroundBlurAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .backgroundBlur(var v) = a.spec { change(&v, st); a.spec = .backgroundBlur(v) } }
    }
    private static func letterSpacing(_ change: @escaping Change<LetterSpacingAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .letterSpacing(var v) = a.spec { change(&v, st); a.spec = .letterSpacing(v) } }
    }
    private static func lineHeight(_ change: @escaping Change<LineHeightAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .lineHeight(var v) = a.spec { change(&v, st); a.spec = .lineHeight(v) } }
    }
    private static func counter(_ change: @escaping Change<CounterAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .counter(var v) = a.spec { change(&v, st); a.spec = .counter(v) } }
    }
    private static func changeText(_ change: @escaping Change<ChangeTextAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .changeText(var v) = a.spec { change(&v, st); a.spec = .changeText(v) } }
    }
    private static func arc(_ change: @escaping Change<ArcAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .arc(var v) = a.spec { change(&v, st); a.spec = .arc(v) } }
    }
    private static func star(_ change: @escaping Change<StarAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .star(var v) = a.spec { change(&v, st); a.spec = .star(v) } }
    }
    private static func volume(_ change: @escaping Change<VolumeAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .volume(var v) = a.spec { change(&v, st); a.spec = .volume(v) } }
    }
    private static func path(_ change: @escaping Change<PathAction>) -> (inout Action, LayerState?) -> Void {
        { a, st in if case .path(var v) = a.spec { change(&v, st); a.spec = .path(v) } }
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

    private func sectionLabel(_ title: String, swap: (() -> Void)? = nil) -> some View {
        sectionLabel(title, swap: swap) { EmptyView() }
    }

    /// A name over controls below it, with any button for them in the
    /// button column. The swap button takes the column when nothing else
    /// does, and otherwise sits just inside it.
    private func sectionLabel<Accessory: View>(_ title: String, swap: (() -> Void)? = nil,
                                               @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            if let swap, Accessory.self != EmptyView.self { SwapButton(action: swap) }
        }
        .rowButton {
            if let swap, Accessory.self == EmptyView.self { SwapButton(action: swap) } else { accessory() }
        }
        .frame(height: Theme.panelRow)
    }

    /// Swaps From and To, where the action has both.
    private var swap: (() -> Void)? {
        guard let inherited, ActionGeometry.swappingEnds(action, from: inherited) != nil else { return nil }
        return { controller.swapActionEnds() }
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
                StackedRow(label: "From", accessory: { IconButton(icon: .plus, help: "Set where it starts", action: set) }) {
                    preview
                    Text("Current")
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private func clearButton(_ visible: Bool, _ action: @escaping () -> Void) -> some View {
        if visible {
            IconButton(icon: .close, help: "Start from wherever the layer is instead", action: action)
        }
    }
}

/// Words typed into a box, kept when Return is pressed or the box is left,
/// so a whole phrase undoes as one step.
private struct WordsField: View {
    let text: String
    let commit: (String) -> Void

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $draft, axis: .vertical)
            .textFieldStyle(.plain)
            .font(ThemeFont.label)
            .lineLimit(1...4)
            .focused($focused)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
            .focusRing(focused)
            .onAppear { draft = text }
            .onChange(of: text) { _, now in if !focused { draft = now } }
            .onSubmit { if draft != text { commit(draft) } }
            .onChange(of: focused) { _, now in if !now, draft != text { commit(draft) } }
    }
}

extension TrimDirection {
    /// As the Trim menus name it.
    var title: String {
        switch self {
        case .startToEnd: "Start to End"
        case .endToStart: "End to Start"
        case .toMiddle: "Both Ends to Middle"
        case .fromMiddle: "Middle to Both Ends"
        }
    }
}
