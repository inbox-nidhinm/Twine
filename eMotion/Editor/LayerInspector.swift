import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// The inspector for one selected layer: where it is, what shape it is, and
/// how it is painted, as designed. Every edit goes through the controller as
/// one undo step.
struct LayerInspector: View {
    let layer: Layer
    let controller: EditorController

    @State private var perCorner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sound has nowhere to be and nothing to show.
            if case .audio = layer.content {} else { transformSection }
            switch layer.content {
            case .video(let v):
                PanelDivider()
                SoundSection(layer: layer, volume: v.volume, isMuted: v.isMuted, controller: controller)
            case .audio(let a):
                SoundSection(layer: layer, volume: a.volume, isMuted: a.isMuted, controller: controller)
            default:
                EmptyView()
            }
            if case .shape(let shape) = layer.content {
                shapeSection(shape.geometry)
                PanelDivider()
                FillSection(layer: layer, shape: shape, controller: controller)
                PanelDivider()
                StrokeSection(layer: layer, shape: shape, controller: controller)
            }
            if case .text(let text) = layer.content {
                PanelDivider()
                TextSection(layer: layer, text: text, controller: controller)
            }
            if case .group(let group) = layer.content {
                ToggleRow(label: "Clip content", isOn: group.clipsContent) {
                    controller.edit(layer.id) { l in
                        if case .group(var g) = l.content {
                            g.clipsContent.toggle()
                            l.content = .group(g)
                        }
                    }
                }
                .help("Hides whatever lies outside the group's box.")
                .padding(.horizontal, Theme.panelPad)
                .padding(.bottom, Theme.panelPad)
            }
            PanelDivider()
            EffectsSection(layer: layer, controller: controller)
        }
    }

    private var t: Transform { layer.transform }

    // MARK: Transform

    private var transformSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Layer") {}
            Group {
                HStack(spacing: 8) {
                    number("X", t.position.x) { l, v in
                        l.transform.position = Vec2(v, l.transform.position.y)
                    }
                    number("Y", t.position.y) { l, v in
                        l.transform.position = Vec2(l.transform.position.x, v)
                    }
                }
                .help("Where the anchor point sits, in pixels")
                if !layer.isGroup {
                    HStack(spacing: 8) {
                        number("W", layer.size.width, accepts: { $0 >= 0 }) { l, v in resize(&l, width: v) }
                        number("H", layer.size.height, accepts: { $0 >= 0 }) { l, v in resize(&l, height: v) }
                    }
                }
                HStack(spacing: 8) {
                    UnitField(unit: "R", value: t.rotation, decimals: 1, suffix: "°") { v in
                        controller.edit(layer.id) { l in l.transform.rotation = v }
                    }
                    .help("Rotation in degrees, clockwise")
                }
                HStack(spacing: 8) {
                    scaleFields
                }
                HStack(spacing: 8) {
                    number("AX", t.anchor.x) { l, v in moveAnchor(&l, x: v) }
                    number("AY", t.anchor.y) { l, v in moveAnchor(&l, y: v) }
                }
                .help("The point the layer turns and scales about, in pixels from its top-left")
                opacity
            }
            .padding(.horizontal, Theme.panelPad)
        }
        .padding(.bottom, Theme.panelPad)
    }

    @ViewBuilder private var scaleFields: some View {
        let scale = t.scale
        if t.isScaleLinked {
            UnitField(unit: "S", value: scale.x * 100, decimals: 1, suffix: "%") { v in
                controller.edit(layer.id) { l in
                    let s = l.transform.scale
                    let ratio = s.x != 0 ? s.y / s.x : 1
                    l.transform.scale = Vec2(v / 100, v / 100 * ratio)
                }
            }
            .help("Scale")
        } else {
            UnitField(unit: "SX", value: scale.x * 100, decimals: 1, suffix: "%") { v in
                controller.edit(layer.id) { l in
                    l.transform.scale = Vec2(v / 100, l.transform.scale.y)
                }
            }
            UnitField(unit: "SY", value: scale.y * 100, decimals: 1, suffix: "%") { v in
                controller.edit(layer.id) { l in
                    l.transform.scale = Vec2(l.transform.scale.x, v / 100)
                }
            }
        }
        IconButton(icon: t.isScaleLinked ? .link : .unlink,
                   help: t.isScaleLinked ? "Scale both ways together" : "Scale each way separately") {
            controller.edit(layer.id) { l in l.transform.isScaleLinked.toggle() }
        }
    }

    private var opacity: some View {
        SliderRow(label: "Opacity", value: layer.opacity * 100, range: 0...100,
                  readout: { "\(Int($0.rounded()))%" },
                  onChange: { v in
                      var l = layer
                      l.opacity = v / 100
                      controller.update([l])
                  },
                  onBegin: { controller.begin("Opacity") },
                  onEnd: { controller.end() })
    }


    /// Resizing from the inspector keeps the layer's top-left where it is and
    /// the anchor in the same place relative to the box, as dragging the
    /// bottom-right handle would.
    private func resize(_ l: inout Layer, width: Double? = nil, height: Double? = nil) {
        let size = l.size
        let target = Size2(width ?? size.width, height ?? size.height)
        let anchor = l.transform.anchor
        let newAnchor = Vec2(size.width > 0 ? anchor.x / size.width * target.width : anchor.x,
                             size.height > 0 ? anchor.y / size.height * target.height : anchor.y)
        let old = Affine.layer(position: l.transform.position, anchor: anchor,
                               scale: l.transform.scale, rotation: l.transform.rotation)
        let topLeft = old.apply(.zero)
        let offset = old.applyToVector(Vec2(-newAnchor.x, -newAnchor.y))
        l.size = target
        l.transform.anchor = newAnchor
        l.transform.position = Vec2(topLeft.x - offset.x, topLeft.y - offset.y)
        // A text box given a width keeps it, and wraps inside it.
        if width != nil, case .text(var t) = l.content {
            t.sizing = .fixedWidth
            l.content = .text(t)
        }
    }

    /// Typing an anchor moves the anchor, not the layer.
    private func moveAnchor(_ l: inout Layer, x: Double? = nil, y: Double? = nil) {
        let anchor = l.transform.anchor
        let target = Vec2(x ?? anchor.x, y ?? anchor.y)
        let old = Affine.layer(position: l.transform.position, anchor: anchor,
                               scale: l.transform.scale, rotation: l.transform.rotation)
        l.transform.anchor = target
        l.transform.position = old.apply(target)
    }

    // MARK: Shape

    @ViewBuilder private func shapeSection(_ geometry: ShapeGeometry) -> some View {
        switch geometry {
        case .rectangle(let radii):
            let r = radii
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    UnitField(unit: "Radius", value: r.topLeft, decimals: 1, accepts: { $0 >= 0 }) { v in
                        setRadii(CornerRadii(all: v))
                    }
                    .help("Corner radius, in pixels")
                    IconButton(icon: .corners, help: perCorner ? "One radius for every corner" : "A radius for each corner") {
                        perCorner.toggle()
                    }
                }
                if perCorner || !r.isUniform {
                    HStack(spacing: 8) {
                        corner("TL", r.topLeft) { c, v in c.topLeft = v }
                        corner("TR", r.topRight) { c, v in c.topRight = v }
                    }
                    HStack(spacing: 8) {
                        corner("BL", r.bottomLeft) { c, v in c.bottomLeft = v }
                        corner("BR", r.bottomRight) { c, v in c.bottomRight = v }
                    }
                }
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.bottom, Theme.panelPad)
        case .polygon(let sides):
            StepRow(label: "Sides", value: sides, range: 3...60) { n in
                setGeometry(.polygon(sides: n))
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.bottom, Theme.panelPad)
        case .star(let points, let inner, let corner):
            VStack(alignment: .leading, spacing: 8) {
                StepRow(label: "Points", value: points, range: 3...60) { n in
                    setGeometry(.star(points: n, innerRadius: inner, cornerRadius: corner))
                }
                HStack(spacing: 8) {
                    UnitField(unit: "Inner", value: inner * 100, decimals: 1, suffix: "%", accepts: { $0 >= 0 }) { v in
                        setGeometry(.star(points: points, innerRadius: v / 100, cornerRadius: corner))
                    }
                    .help("How far in the inner points sit, as a share of the outer ones")
                    UnitField(unit: "Radius", value: corner, decimals: 1, accepts: { $0 >= 0 }) { v in
                        setGeometry(.star(points: points, innerRadius: inner, cornerRadius: v))
                    }
                    .help("Rounds every point, in pixels")
                }
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.bottom, Theme.panelPad)
        case .ellipse(let arc):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    UnitField(unit: "Start", value: arc.start, decimals: 1, suffix: "°") { v in
                        setGeometry(.ellipse(arc: EllipseArc(start: v, end: v + (arc.end - arc.start), innerRadius: arc.innerRadius)))
                    }
                    .help("Where the slice starts, in degrees clockwise from three o'clock")
                    UnitField(unit: "Sweep", value: arc.end - arc.start, decimals: 1, suffix: "°",
                              accepts: { $0 >= 0 && $0 <= 360 }) { v in
                        setGeometry(.ellipse(arc: EllipseArc(start: arc.start, end: arc.start + v, innerRadius: arc.innerRadius)))
                    }
                    .help("How far round the slice goes. 360° is the whole ellipse.")
                }
                UnitField(unit: "Ratio", value: arc.innerRadius * 100, decimals: 1, suffix: "%", accepts: { $0 >= 0 && $0 < 100 }) { v in
                    setGeometry(.ellipse(arc: EllipseArc(start: arc.start, end: arc.end, innerRadius: v / 100)))
                }
                .help("The hole in the middle, as a share of the ellipse: 0% is solid, 80% a thin ring")
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.bottom, Theme.panelPad)
        default:
            EmptyView()
        }
    }

    private func corner(_ unit: String, _ value: Double, _ set: @escaping (inout CornerRadii, Double) -> Void) -> some View {
        UnitField(unit: unit, value: value, decimals: 1, accepts: { $0 >= 0 }) { v in
            guard case .rectangle(let radii) = layer.shapeGeometry else { return }
            var r = radii
            set(&r, v)
            setRadii(r)
        }
    }

    private func setRadii(_ r: CornerRadii) {
        guard case .rectangle = layer.shapeGeometry else { return }
        setGeometry(.rectangle(cornerRadii: r))
    }

    private func setGeometry(_ geometry: ShapeGeometry) {
        controller.edit(layer.id) { l in
            if case .shape(var s) = l.content {
                s.geometry = geometry
                l.content = .shape(s)
            }
        }
    }

    // MARK: Helpers

    private func number(_ unit: String, _ value: Double, accepts: @escaping (Double) -> Bool = { _ in true },
                        _ set: @escaping (inout Layer, Double) -> Void) -> some View {
        UnitField(unit: unit, value: value, decimals: 1, accepts: accepts) { v in
            controller.edit(layer.id) { l in set(&l, v) }
        }
    }
}

// MARK: - Sound

/// A video's or a sound's level, for preview and export alike.
private struct SoundSection: View {
    let layer: Layer
    let volume: Double
    let isMuted: Bool
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Sound") {
                IconButton(icon: isMuted ? .speakerOff : .speaker, help: isMuted ? "Unmute" : "Mute") {
                    controller.edit(layer.id) { l in l.content = Self.with(l.content) { $1.toggle() } }
                }
            }
            SliderRow(label: "Volume", value: volume * 100, range: 0...200, readout: { "\(Int($0.rounded()))%" },
                      onChange: { v in
                          var l = layer
                          l.content = Self.with(l.content) { level, _ in level = v / 100 }
                          controller.update([l])
                      },
                      onBegin: { controller.begin("Volume") },
                      onEnd: { controller.end() })
                .opacity(isMuted ? 0.4 : 1)
                .padding(.horizontal, Theme.panelPad)
                .help("100% is the file's own level")
        }
        .padding(.bottom, Theme.panelPad)
    }

    /// The content with its volume and mute changed, whichever kind it is.
    static func with(_ content: LayerContent, _ change: (inout Double, inout Bool) -> Void) -> LayerContent {
        switch content {
        case .video(var v):
            change(&v.volume, &v.isMuted)
            return .video(v)
        case .audio(var a):
            change(&a.volume, &a.isMuted)
            return .audio(a)
        default:
            return content
        }
    }
}

// MARK: - Fill

private struct FillSection: View {
    let layer: Layer
    let shape: ShapeContent
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Fill") {
                if let fill = shape.fills.first {
                    IconButton(icon: fill.isEnabled ? .eye : .eyeSlash, help: fill.isEnabled ? "Hide the fill" : "Show the fill") {
                        editShape { $0.fills[0].isEnabled.toggle() }
                    }
                }
                if shape.fills.isEmpty {
                    IconButton(icon: .plus, help: "Add a fill") {
                        editShape { $0.fills = [Fill(paint: .color(LayerFactory.defaultFill))] }
                    }
                } else {
                    IconButton(icon: .minus, help: "Remove the fill") { editShape { $0.fills.removeFirst() } }
                }
            }
            if let fill = shape.fills.first {
                VStack(alignment: .leading, spacing: 8) {
                    SegmentRow(selection: fill.paint.kindName, options: ["Solid", "Linear", "Radial"], title: { $0 }) { kind in
                        editShape { $0.fills[0].paint = fill.paint.converted(to: kind) }
                    }
                    PaintEditor(paint: fill.paint, isEnabled: fill.isEnabled, controller: controller, layer: layer,
                                title: "Fill",
                                change: { paint in editedShape { $0.fills[0].paint = paint } },
                                toggle: { editShape { $0.fills[0].isEnabled.toggle() } })
                }
                .padding(.horizontal, Theme.panelPad)
            }
        }
        .padding(.bottom, Theme.panelPad)
    }

    private func editShape(_ change: (inout ShapeContent) -> Void) {
        controller.edit(layer.id) { l in l.content = .shape(edited(change)) }
    }

    private func edited(_ change: (inout ShapeContent) -> Void) -> ShapeContent {
        var s = shape
        change(&s)
        return s
    }

    /// For the colour well and hex field, which report whole layers.
    private func editedShape(_ change: (inout ShapeContent) -> Void) -> Layer {
        var l = layer
        l.content = .shape(edited(change))
        return l
    }
}

// MARK: - Stroke

private struct StrokeSection: View {
    let layer: Layer
    let shape: ShapeContent
    let controller: EditorController



    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Stroke") {
                if let stroke = shape.strokes.first {
                    IconButton(icon: stroke.isEnabled ? .eye : .eyeSlash, help: stroke.isEnabled ? "Hide the stroke" : "Show the stroke") {
                        editShape { $0.strokes[0].isEnabled.toggle() }
                    }
                }
                if shape.strokes.isEmpty {
                    IconButton(icon: .plus, help: "Add a stroke") {
                        editShape { $0.strokes = [Stroke(paint: .color(LayerFactory.defaultStroke), width: 2)] }
                    }
                } else {
                    IconButton(icon: .minus, help: "Remove the stroke") { editShape { $0.strokes.removeFirst() } }
                }
            }
            if let stroke = shape.strokes.first {
                VStack(alignment: .leading, spacing: 8) {
                    PaintEditor(paint: stroke.paint, isEnabled: stroke.isEnabled, controller: controller, layer: layer,
                                title: "Stroke",
                                change: { paint in
                                    var l = layer
                                    var s = shape
                                    s.strokes[0].paint = paint
                                    l.content = .shape(s)
                                    return l
                                },
                                toggle: { editShape { $0.strokes[0].isEnabled.toggle() } })
                    LabeledRow(label: "Width") {
                        UnitField(value: stroke.width, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                            editShape { $0.strokes[0].width = v }
                        }
                    }
                    LabeledRow(label: "Trim start") {
                        UnitField(value: stroke.trimStart * 100, decimals: 1, suffix: "%",
                                  accepts: { $0 >= 0 && $0 <= 100 }) { v in
                            editShape { $0.strokes[0].trimStart = v / 100 }
                        }
                    }
                    .help("How much of the path is left undrawn at its start. Animate it to draw a line on.")
                    LabeledRow(label: "Trim end") {
                        UnitField(value: stroke.trimEnd * 100, decimals: 1, suffix: "%",
                                  accepts: { $0 >= 0 && $0 <= 100 }) { v in
                            editShape { $0.strokes[0].trimEnd = v / 100 }
                        }
                    }
                    .help("Where along the path the stroke stops")
                    if shape.geometry.isClosed {
                        SegmentRow(selection: stroke.alignment, options: StrokeAlignment.allCases,
                                   title: { $0.rawValue.capitalized }) { a in
                            editShape { $0.strokes[0].alignment = a }
                        }
                        .help("Whether the stroke sits centred on the edge, inside it, or outside it")
                    }
                    SegmentRow(selection: stroke.cap, options: LineCap.allCases, title: { $0.rawValue.capitalized }) { c in
                        editShape { $0.strokes[0].cap = c }
                    }
                    .help("The ends of open lines and dashes")
                    SegmentRow(selection: stroke.join, options: LineJoin.allCases, title: { $0.rawValue.capitalized }) { j in
                        editShape { $0.strokes[0].join = j }
                    }
                    .help("The corners")
                    HStack(spacing: 8) {
                        UnitField(unit: "Dash", value: stroke.dashPattern.first ?? 0, decimals: 1, accepts: { $0 >= 0 }) { v in
                            editShape { s in
                                let gap = s.strokes[0].dashPattern.count > 1 ? s.strokes[0].dashPattern[1] : v
                                s.strokes[0].dashPattern = v > 0 ? [v, gap] : []
                            }
                        }
                        UnitField(unit: "Gap", value: stroke.dashPattern.count > 1 ? stroke.dashPattern[1] : 0,
                                  decimals: 1, accepts: { $0 >= 0 }) { v in
                            editShape { s in
                                let dash = s.strokes[0].dashPattern.first ?? max(v, 1)
                                s.strokes[0].dashPattern = [dash, v]
                            }
                        }
                    }
                    .help("Dash and gap lengths in pixels. A dash of 0 is a solid line.")
                }
                .padding(.horizontal, Theme.panelPad)
            }
        }
        .padding(.bottom, Theme.panelPad)
    }

    private func editShape(_ change: (inout ShapeContent) -> Void) {
        var s = shape
        change(&s)
        controller.edit(layer.id) { l in l.content = .shape(s) }
    }
}

// MARK: - Paint

/// A paint's colours: one well for a solid colour, a well per end for a
/// gradient, each with its hex and its opacity.
private struct PaintEditor: View {
    let paint: Paint
    let isEnabled: Bool
    let controller: EditorController
    let layer: Layer
    let title: String
    /// Builds the whole edited layer for a new paint.
    let change: (Paint) -> Layer
    let toggle: () -> Void


    var body: some View {
        switch paint {
        case .solid(let color):
            colorRow(color) { c in .solid(c) }
        case .linearGradient(let g), .radialGradient(let g):
            let stops = g.stops
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    colorRow(stop.color) { c in
                        var s = stops
                        s[index].color = c
                        var gradient = g
                        gradient.stops = s
                        return paint.withGradient(gradient)
                    }
                }
            }
        }
    }

    private func colorRow(_ color: RGBA, _ make: @escaping (RGBA) -> Paint) -> some View {
        HStack(spacing: 6) {
            ColorWell(color: color, size: Theme.control, title: title,
                      onChange: { controller.update([change(make($0))]) },
                      onBegin: { controller.begin("Colour") },
                      onEnd: { controller.end() })
            HexField(color: color) { controller.perform(.updateLayers([change(make($0))])) }
            UnitField(value: color.a * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                var c = color
                c.a = v / 100
                controller.perform(.updateLayers([change(make(c))]))
            }
            .frame(width: 58)
            .help("Opacity of this colour")
        }
    }
}

extension Paint {
    var isSolid: Bool {
        if case .solid = self { return true }
        return false
    }

    var kindName: String {
        switch self {
        case .solid: return "Solid"
        case .linearGradient: return "Linear"
        case .radialGradient: return "Radial"
        }
    }

    /// The same paint as another kind, carrying its colours across: a solid
    /// becomes a gradient from its colour to transparent, and a gradient
    /// becomes a solid of its first colour.
    func converted(to kind: String) -> Paint {
        switch (self, kind) {
        case (.solid(let c), "Linear"), (.solid(let c), "Radial"):
            var clear = c
            clear.a = 0
            let g = MotionModel.Gradient(stops: [GradientStop(position: 0, color: c), GradientStop(position: 1, color: clear)],
                             start: kind == "Radial" ? Vec2(0.5, 0.5) : Vec2(0, 0.5),
                             end: kind == "Radial" ? Vec2(1, 0.5) : Vec2(1, 0.5))
            return kind == "Radial" ? .radialGradient(g) : .linearGradient(g)
        case (.linearGradient(let g), "Solid"), (.radialGradient(let g), "Solid"):
            return .color(g.stops.first?.color ?? .white)
        case (.linearGradient(var g), "Radial"):
            g.start = Vec2(0.5, 0.5)
            g.end = Vec2(1, 0.5)
            return .radialGradient(g)
        case (.radialGradient(var g), "Linear"):
            g.start = Vec2(0, 0.5)
            g.end = Vec2(1, 0.5)
            return .linearGradient(g)
        default:
            return self
        }
    }

    func withGradient(_ g: MotionModel.Gradient) -> Paint {
        switch self {
        case .radialGradient: return .radialGradient(g)
        default: return .linearGradient(g)
        }
    }
}

// MARK: - Effects

private struct EffectsSection: View {
    let layer: Layer
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var addFrame: CGRect = .zero


    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Effects") {
                IconButton(icon: .plus, help: "Add a shadow or a blur") {
                    var entries: [MenuEntry] = [
                        .item("Drop Shadow") { add(.dropShadow(DropShadow())) },
                        .item("Layer Blur") { add(.layerBlur(LayerBlur())) },
                    ]
                    // It follows a shape's outline, so only shapes have one.
                    if case .shape = layer.content {
                        entries.append(.item("Background Blur") { add(.backgroundBlur(BackgroundBlur())) })
                    }
                    menus.show(entries, at: CGPoint(x: addFrame.maxX - Theme.menuMinWidth, y: addFrame.maxY + 4))
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { addFrame = $0 }
            }
            ForEach(Array(layer.effects.enumerated()), id: \.element.id) { index, effect in
                effectRows(effect, index: index)
                    .padding(.horizontal, Theme.panelPad)
            }
        }
        .padding(.bottom, Theme.panelPad)
    }

    @ViewBuilder private func effectRows(_ effect: Effect, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(effect.title)
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 0)
                IconButton(icon: effect.isEnabled ? .eye : .eyeSlash, help: effect.isEnabled ? "Hide" : "Show") {
                    edit(index) { $0.isEnabled.toggle() }
                }
                IconButton(icon: .minus, help: "Remove") {
                    controller.edit(layer.id) { l in l.effects.remove(at: index) }
                }
            }
            switch effect.kind {
            case .dropShadow(let s):
                HStack(spacing: 8) {
                    ColorWell(color: s.color, size: Theme.control, title: "Shadow",
                              onChange: { c in controller.update([withShadow(index) { $0.color = c }]) },
                              onBegin: { controller.begin("Shadow Colour") },
                              onEnd: { controller.end() })
                    HexField(color: s.color) { c in
                        controller.perform(.updateLayers([withShadow(index) { $0.color = c }]))
                    }
                    UnitField(value: s.opacity * 100, decimals: 0, suffix: "%",
                              accepts: { $0 >= 0 && $0 <= 100 }) { v in
                        controller.perform(.updateLayers([withShadow(index) { $0.opacity = v / 100 }]))
                    }
                    .frame(width: Theme.labelWidth)
                    .help("Shadow opacity")
                }
                HStack(spacing: 8) {
                    field(index, "X", s.offset.x) { sh, v in
                        sh.offset = Vec2(v, sh.offset.y)
                    }
                    field(index, "Y", s.offset.y) { sh, v in
                        sh.offset = Vec2(sh.offset.x, v)
                    }
                }
                HStack(spacing: 8) {
                    field(index, "Blur", s.blur, min: 0) { sh, v in sh.blur = v }
                    field(index, "Spread", s.spread) { sh, v in sh.spread = v }
                        .help("Grows the shadow past the shape before it is blurred, or shrinks it with a negative number. Shapes only.")
                }
            case .layerBlur(let b):
                LabeledRow(label: "Radius") {
                    UnitField(value: b.radius, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                        edit(index) { e in
                            if case .layerBlur(var blur) = e.kind {
                                blur.radius = v
                                e.kind = .layerBlur(blur)
                            }
                        }
                    }
                }
            case .backgroundBlur(let b):
                HStack(spacing: 8) {
                    UnitField(unit: "Blur", value: b.radius, decimals: 1, accepts: { $0 >= 0 }) { v in
                        editBackgroundBlur(index) { $0.radius = v }
                    }
                    .help("How much the background behind the layer is blurred. It shows through where the fill is see-through.")
                    UnitField(value: b.blend * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                        editBackgroundBlur(index) { $0.blend = v / 100 }
                    }
                    .help("Blend: how much of the blurred background shows over the sharp one.")
                }
            }
        }
    }

    private func field(_ index: Int, _ unit: String, _ value: Double, min: Double? = nil,
                       _ set: @escaping (inout DropShadow, Double) -> Void) -> some View {
        UnitField(unit: unit, value: value, decimals: 1, accepts: { v in min.map { v >= $0 } ?? true }) { v in
            controller.perform(.updateLayers([withShadow(index) { set(&$0, v) }]))
        }
    }


    private func editBackgroundBlur(_ index: Int, _ change: @escaping (inout BackgroundBlur) -> Void) {
        edit(index) { e in
            if case .backgroundBlur(var blur) = e.kind {
                change(&blur)
                e.kind = .backgroundBlur(blur)
            }
        }
    }

    private func add(_ kind: EffectKind) {
        controller.edit(layer.id) { l in l.effects.append(Effect(kind: kind)) }
    }

    private func edit(_ index: Int, _ change: (inout Effect) -> Void) {
        controller.edit(layer.id) { l in
            guard l.effects.indices.contains(index) else { return }
            change(&l.effects[index])
        }
    }

    private func withShadow(_ index: Int, _ change: (inout DropShadow) -> Void) -> Layer {
        var l = layer
        if l.effects.indices.contains(index), case .dropShadow(var s) = l.effects[index].kind {
            change(&s)
            l.effects[index].kind = .dropShadow(s)
        }
        return l
    }
}

extension Effect {
    var title: String {
        switch kind {
        case .dropShadow: return "Drop Shadow"
        case .layerBlur: return "Layer Blur"
        case .backgroundBlur: return "Background Blur"
        }
    }
}
