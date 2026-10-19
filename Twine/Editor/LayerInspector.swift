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
        // A template's slot shows what it holds, and nothing else.
        if let slot = controller.templateSlot(layer.id) {
            TemplateSlotSection(slot: layer, template: slot.template, index: slot.index, controller: controller)
        } else {
            sections
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sound has nowhere to be and nothing to show.
            if case .audio = layer.content {} else {
                positionSection
                PanelDivider()
                layoutSection
                if let setup = layer.template {
                    // A template sets its own camera.
                    PanelDivider()
                    TemplateSection(layer: layer, setup: setup, controller: controller)
                } else if layer.isFrame {
                    PanelDivider()
                    SpaceSection(layer: layer, controller: controller)
                }
                PanelDivider()
                appearanceSection
            }
            if case .video(let v) = layer.content {
                PanelDivider()
                VideoSection(layer: layer, video: v, controller: controller)
            }
            switch layer.content {
            case .video(let v) where controller.project.hasSound(layer):
                // Only a clip with a sound track has a sound to set.
                PanelDivider()
                SoundSection(layer: layer, volume: v.volume, isMuted: v.isMuted, controller: controller)
            case .audio(let a):
                SoundSection(layer: layer, volume: a.volume, isMuted: a.isMuted, controller: controller)
            default:
                EmptyView()
            }
            if case .shape(let shape) = layer.content {
                PanelDivider()
                FillSection(layer: layer, shape: shape, controller: controller)
                PanelDivider()
                StrokeSection(layer: layer, shape: shape, controller: controller)
            }
            if case .text(let text) = layer.content {
                PanelDivider()
                TextSection(layer: layer, text: text, controller: controller)
                PanelDivider()
                TextFillSection(layer: layer, text: text, controller: controller)
                PanelDivider()
                TextStrokeSection(layer: layer, text: text, controller: controller)
            }
            if layer.isFrame, let look = layer.look {
                PanelDivider()
                FillSection(layer: layer, shape: look, controller: controller)
                PanelDivider()
                StrokeSection(layer: layer, shape: look, controller: controller)
            }
            PanelDivider()
            EffectsSection(layer: layer, controller: controller)
            // Masks are made from the layers' right-click menu, as in Figma;
            // a mask says so here, where it can stop being one.
            if layer.isMask {
                PanelDivider()
                MaskSection(layer: layer, controller: controller)
            }
            PanelDivider()
        }
    }

    private var t: Transform { layer.transform }

    /// Figma's blend modes, in its groups.
    private func blendEntries() -> [MenuEntry] {
        var entries: [MenuEntry] = []
        for (i, group) in BlendMode.groups.enumerated() {
            if i > 0 { entries.append(.separator) }
            entries += group.map { mode in
                .item(mode.title, checked: mode == layer.blendMode) {
                    controller.edit(layer.id) { $0.blendMode = mode }
                }
            }
        }
        return entries
    }

    // MARK: Position

    /// Where the layer sits: lined up with the composition, its place, its
    /// turn, and the point it turns about.
    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Position") {}
            AlignRow(controller: controller)
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
                // Z shows in a frame in 3D, and wherever one is set.
                if t.z != 0 || controller.project.space3D(holding: layer.id) != nil {
                    HStack(spacing: 8) {
                        number("Z", t.z) { l, v in l.transform.z = v }
                            .help("How far towards you it sits, in pixels; negative is further away")
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    UnitField(unit: "R", value: t.rotation, decimals: 1, suffix: "°") { v in
                        controller.edit(layer.id) { l in l.transform.rotation = v }
                    }
                    .help("Rotation in degrees, clockwise")
                    AnchorPicker(chosen: anchorFraction) { fx, fy in
                        controller.edit(layer.id) { l in moveAnchor(&l, x: l.size.width * fx, y: l.size.height * fy) }
                    }
                    .help("The point the layer turns and scales about: a corner, the middle of an edge, or the centre")
                }
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }

    // MARK: Layout

    /// How big the layer is and what shape: its size, its scale, its
    /// corners or points, and for a group or frame, whether it clips.
    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Layout") {}
            Group {
                // A group's size is only where it was made; a frame's is its own.
                if !layer.isGroup || layer.isFrame {
                    HStack(spacing: 8) {
                        number("W", layer.size.width, accepts: { $0 >= 0 }) { l, v in l = l.resized(toWidth: v) }
                        number("H", layer.size.height, accepts: { $0 >= 0 }) { l, v in l = l.resized(toHeight: v) }
                    }
                    .rowButton { widthHeightLink }
                }
                scaleRow
                if let geometry = layer.look?.geometry { shapeFields(geometry) }
                if case .group(let group) = layer.content {
                    CheckRow(label: "Clip content", isOn: group.clipsContent) {
                        controller.edit(layer.id) { l in
                            if case .group(var g) = l.content {
                                g.clipsContent.toggle()
                                l.content = .group(g)
                            }
                        }
                    }
                    .help(layer.isFrame ? "Hides whatever lies outside the frame, round its corners too."
                                        : "Hides whatever lies outside the group's box.")
                }
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }

    /// Keeps width and height in proportion. Text sets its own height, so it
    /// has none.
    @ViewBuilder private var widthHeightLink: some View {
        if case .text = layer.content {
            EmptyView()
        } else {
            IconButton(icon: layer.keepsProportions ? .link : .unlink,
                       help: layer.keepsProportions ? "Keeps proportions: width and height change together"
                                                    : "Width and height change separately") {
                controller.edit(layer.id) { l in l.keepsProportions.toggle() }
            }
        }
    }

    /// Where the anchor sits as fractions of the box, when it is on one of
    /// the nine points the picker offers.
    private var anchorFraction: (Double, Double)? {
        let size = layer.size
        guard size.width > 0, size.height > 0 else { return nil }
        let fx = t.anchor.x / size.width, fy = t.anchor.y / size.height
        func snapped(_ f: Double) -> Double? { [0, 0.5, 1].first { abs($0 - f) < 1e-6 } }
        guard let x = snapped(fx), let y = snapped(fy) else { return nil }
        return (x, y)
    }

    /// Both ways always, with their own link in the column.
    private var scaleRow: some View {
        let scale = t.scale
        return HStack(spacing: 8) {
            UnitField(unit: "SX", value: scale.x * 100, decimals: 1, suffix: "%") { v in
                controller.edit(layer.id) { l in
                    let s = l.transform.scale
                    let y = l.transform.isScaleLinked ? (s.x != 0 ? s.y / s.x * v / 100 : v / 100) : s.y
                    l.transform.scale = Vec2(v / 100, y)
                }
            }
            .help("Scale across")
            UnitField(unit: "SY", value: scale.y * 100, decimals: 1, suffix: "%") { v in
                controller.edit(layer.id) { l in
                    let s = l.transform.scale
                    let x = l.transform.isScaleLinked ? (s.y != 0 ? s.x / s.y * v / 100 : v / 100) : s.x
                    l.transform.scale = Vec2(x, v / 100)
                }
            }
            .help("Scale down")
        }
        .rowButton {
            IconButton(icon: t.isScaleLinked ? .link : .unlink,
                       help: t.isScaleLinked ? "Scales both ways together" : "Scales each way separately") {
                controller.edit(layer.id) { l in l.transform.isScaleLinked.toggle() }
            }
        }
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Appearance") {}
            BlendOpacityRow(blend: layer.blendMode.title, entries: blendEntries,
                            opacity: layer.opacity, isGroup: layer.isGroup) { v in
                controller.edit(layer.id) { $0.opacity = v }
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }


    /// Typing an anchor moves the anchor, not the layer.
    private func moveAnchor(_ l: inout Layer, x: Double? = nil, y: Double? = nil) {
        let anchor = l.transform.anchor
        let target = Vec2(x ?? anchor.x, y ?? anchor.y)
        let old = Affine.layer(position: l.transform.position, anchor: anchor,
                               scale: l.transform.scale, rotation: l.transform.rotation, skew: l.transform.skew)
        l.transform.anchor = target
        l.transform.position = old.apply(target)
    }

    // MARK: Shape

    @ViewBuilder private func shapeFields(_ geometry: ShapeGeometry) -> some View {
        switch geometry {
        case .rectangle(let radii):
            let r = radii
            VStack(alignment: .leading, spacing: 8) {
                cornerRadiusField
                .rowButton {
                    IconButton(icon: .corners, help: perCorner ? "One radius for every corner" : "A radius for each corner") {
                        perCorner.toggle()
                    }
                }
                if perCorner || !r.isUniform {
                    HStack(spacing: 8) {
                        corner(.cornerTopLeft, r.topLeft) { c, v in c.topLeft = v }
                        corner(.cornerTopRight, r.topRight) { c, v in c.topRight = v }
                    }
                    HStack(spacing: 8) {
                        corner(.cornerBottomLeft, r.bottomLeft) { c, v in c.bottomLeft = v }
                        corner(.cornerBottomRight, r.bottomRight) { c, v in c.bottomRight = v }
                    }
                }
            }
        case .polygon(let sides, let corner):
            VStack(alignment: .leading, spacing: 8) {
                StepRow(label: "Sides", value: sides, range: 3...60) { n in
                    setGeometry(.polygon(sides: n, cornerRadius: corner))
                }
                cornerRadiusField
            }
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
                    cornerRadiusField
                }
            }
        case .ellipse(let arc):
            // One joined field, as Figma has it: where the slice starts, how
            // much of a full turn it sweeps, and the hole in the middle.
            JoinedFields {
                UnitField(icon: .arc, corner: 0, value: arc.start, decimals: 1, suffix: "°") { v in
                    setGeometry(.ellipse(arc: EllipseArc(start: v, end: v + (arc.end - arc.start), innerRadius: arc.innerRadius)))
                }
                .help("Start: where the slice begins, in degrees clockwise from three o'clock")
                UnitField(corner: 0, value: (arc.end - arc.start) / 360 * 100, decimals: 2, suffix: "%",
                          accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    setGeometry(.ellipse(arc: EllipseArc(start: arc.start, end: arc.start + v / 100 * 360, innerRadius: arc.innerRadius)))
                }
                .frame(width: 62)
                .help("Sweep: how much of a full turn the slice goes round. 100% is the whole ellipse.")
                UnitField(corner: 0, value: arc.innerRadius * 100, decimals: 1, suffix: "%", accepts: { $0 >= 0 && $0 < 100 }) { v in
                    setGeometry(.ellipse(arc: EllipseArc(start: arc.start, end: arc.end, innerRadius: v / 100)))
                }
                .frame(width: 48)
                .help("Ratio: the hole in the middle, as a share of the ellipse. 0% is solid, 80% a thin ring.")
            }
        case .path:
            cornerRadiusField
        case .line:
            EmptyView()
        }
    }

    /// The points picked on this layer's points, nil when none are.
    private var pickedRefs: Set<PointRef>? {
        guard let picked = controller.editor.pickedPoints, picked.layerID == layer.id else { return nil }
        return picked.refs
    }

    /// One radius for the corners: the picked points' while some are
    /// picked, else every corner's. Where they differ, the largest shows
    /// dimmed, and typing sets them all.
    private var cornerRadiusField: some View {
        let refs = pickedRefs
        var radii = CornerEditing.radii(of: layer, at: refs)
        if radii.isEmpty, case .rectangle(let r)? = layer.look?.geometry {
            // A frame's corners.
            radii = [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft]
        }
        let shared = radii.allSatisfy { $0 == radii.first } ? radii.first : nil
        return OptionalField(unit: "Radius", value: shared, placeholder: radii.max() ?? 0, decimals: 1,
                             accepts: { $0 >= 0 }) { v in
            guard let v else { return }
            if CornerEditing.hasCorners(layer) {
                controller.setCornerRadius(v, of: layer.id, at: refs)
            } else {
                setRadii(CornerRadii(all: v))
            }
        }
        .help(refs == nil ? "Corner radius, in pixels" : "Corner radius of the picked points, in pixels")
    }

    private func corner(_ icon: Icon, _ value: Double, _ set: @escaping (inout CornerRadii, Double) -> Void) -> some View {
        UnitField(icon: icon, value: value, decimals: 1, accepts: { $0 >= 0 }) { v in
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
            if var s = l.look {
                s.geometry = geometry
                l.look = s
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

// MARK: - Anchor

/// The nine places an anchor can go, as a small box: its corners, the
/// middles of its edges and its centre. The chosen one is filled; an anchor
/// dragged anywhere else on the canvas leaves none chosen.
struct AnchorPicker: View {
    /// Fractions of the box across and down, nil when the anchor is
    /// elsewhere.
    let chosen: (Double, Double)?
    let pick: (Double, Double) -> Void

    private let fractions: [Double] = [0, 0.5, 1]
    /// Each point's clickable box. The columns sit at the tray's edges, so
    /// the points are inset only by half a box and the tray's padding.
    private let cell = CGSize(width: 20, height: 14)

    var body: some View {
        VStack(spacing: 0) {
            ForEach(fractions, id: \.self) { fy in
                HStack(spacing: 0) {
                    ForEach(fractions, id: \.self) { fx in
                        if fx > 0 { Spacer(minLength: 0) }
                        AnchorDot(isChosen: chosen.map { $0.0 == fx && $0.1 == fy } ?? false) { pick(fx, fy) }
                            .frame(width: cell.width, height: cell.height)
                    }
                }
            }
        }
        .padding(Theme.menuPad)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
    }
}

private struct AnchorDot: View {
    let isChosen: Bool
    let pick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            Circle()
                .fill(isChosen ? Theme.textPrimary : hovering ? Theme.textSecondary : Theme.textTertiary)
                .frame(width: isChosen ? 7 : 5, height: isChosen ? 7 : 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Appearance

/// How a layer mixes with what is behind it and how much of it shows, side
/// by side, as Figma has them. For one layer or several.
struct BlendOpacityRow: View {
    let blend: String
    let entries: () -> [MenuEntry]
    let opacity: Double
    var isGroup = false
    /// 0 to 1.
    let setOpacity: (Double) -> Void

    var body: some View {
        HStack(spacing: 8) {
            MenuField(value: blend, entries: entries, height: Theme.control)
                .help(isGroup ? "Blend: how the layer mixes with what is behind it. At Normal, what is inside a group or frame blends through it, as Figma's Pass Through does."
                              : "Blend: how the layer mixes with what is behind it")
            UnitField(value: opacity * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                setOpacity(v / 100)
            }
            .frame(width: Theme.labelWidth)
            .help("Opacity")
        }
    }
}

// MARK: - Sound

/// A layer's Sound section when it has a sound (a sound, or a video with a
/// sound track), for Animate's inspector too, the user's choice on 29
/// September 2026: the level every Volume action starts from.
struct LayerSoundSection: View {
    let layer: Layer
    let controller: EditorController

    var body: some View {
        switch layer.content {
        case .video(let v) where controller.project.hasSound(layer):
            SoundSection(layer: layer, volume: v.volume, isMuted: v.isMuted, controller: controller)
        case .audio(let a):
            SoundSection(layer: layer, volume: a.volume, isMuted: a.isMuted, controller: controller)
        default:
            EmptyView()
        }
    }
}

/// A video's or a sound's level, for preview and export alike.
private struct SoundSection: View {
    let layer: Layer
    let volume: Double
    let isMuted: Bool
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Sound") {}
            SliderRow(label: "Volume", value: min(volume, 1) * 100, range: 0...100, readout: { "\(Int($0.rounded()))%" },
                      onChange: { v in
                          var l = layer
                          // There is no mute button (the user asked for the
                          // slider alone), so moving it brings back a sound
                          // muted before.
                          l.content = Self.with(l.content) { level, muted in
                              level = min(max(v, 0), 100) / 100
                              muted = false
                          }
                          controller.update([l])
                      },
                      onBegin: { controller.begin("Volume") },
                      onEnd: { controller.end() })
                .opacity(isMuted ? 0.4 : 1)
                .help("100% is the file's own level")
                .gridBody()
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
                IconButton(icon: .plus, help: shape.fills.isEmpty ? "Add a fill" : "Add a fill on top") {
                    editShape { s in
                        // The first in the shape's own grey; another, a
                        // see-through black over what is there.
                        s.fills.append(Fill(paint: .color(s.fills.isEmpty ? LayerFactory.defaultFill : RGBA(0, 0, 0, 0.2))))
                    }
                }
            }
            // Every fill, the top one (the one a Colour action changes)
            // first, as the layers panel lists layers (4 October 2026; only
            // the top one showed before).
            ForEach(Array(shape.fills.enumerated()).reversed(), id: \.element.id) { index, fill in
                fillRows(fill, index: index)
                    .gridBody()
            }
        }
        .sectionPadding(empty: shape.fills.isEmpty)
    }

    @ViewBuilder private func fillRows(_ fill: Fill, index i: Int) -> some View {
        // One picture fill a layer: Image is offered where it is, or on any
        // fill while there is none.
        let picture = shape.pictureIndex
        let kinds = picture == nil || picture == i ? ["Solid", "Linear", "Radial", "Angular", "Image"]
                                                   : ["Solid", "Linear", "Radial", "Angular"]
        VStack(alignment: .leading, spacing: 8) {
            InspectorItemTitle(icon: Icon.fillKind(fill.paint.kindName), title: "Fill") {
                editShape { s in if s.fills.indices.contains(i) { s.fills.remove(at: i) } }
            }
            SegmentRow(selection: fill.paint.kindName, options: kinds, title: { $0 }, icon: Icon.fillKind) { kind in
                if kind == "Image" {
                    if !fill.paint.isImage { controller.fillWithPicture(layer.id, at: i) }
                } else {
                    editShape { s in if s.fills.indices.contains(i) { s.fills[i].paint = fill.paint.converted(to: kind) } }
                    // Working on the gradient brings back its line, on this fill.
                    controller.editor.hidesGradient = false
                    if kind != "Solid" { controller.editor.gradient = GradientEdit(layerID: layer.id, slot: .fill(i)) }
                }
            }
            .rowButton {
                // Show and hide the fill, on its first row.
                IconButton(icon: fill.isEnabled ? .eye : .eyeSlash, help: fill.isEnabled ? "Hide the fill" : "Show the fill") {
                    editShape { s in if s.fills.indices.contains(i) { s.fills[i].isEnabled.toggle() } }
                }
            }
            if let picture = fill.paint.imagePaint {
                PictureFields(layer: layer, paint: picture, controller: controller)
            } else {
                PaintEditor(paint: fill.paint, isEnabled: fill.isEnabled, controller: controller, layer: layer,
                            title: "Fill", slot: .fill(i),
                            change: { paint in editedShape { s in if s.fills.indices.contains(i) { s.fills[i].paint = paint } } },
                            toggle: { editShape { s in if s.fills.indices.contains(i) { s.fills[i].isEnabled.toggle() } } })
            }
        }
    }

    private func editShape(_ change: (inout ShapeContent) -> Void) {
        controller.edit(layer.id) { l in l.look = edited(change) }
    }

    private func edited(_ change: (inout ShapeContent) -> Void) -> ShapeContent {
        var s = shape
        change(&s)
        return s
    }

    /// For the colour well and hex field, which report whole layers.
    private func editedShape(_ change: (inout ShapeContent) -> Void) -> Layer {
        var l = layer
        l.look = edited(change)
        return l
    }
}

// MARK: - Pictures and video

/// A picture fill: the picture, Replace, how it fills the shape, its turn,
/// and for tiles, their size.
private struct PictureFields: View {
    let layer: Layer
    let paint: MotionModel.ImagePaint
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                PictureWell(image: controller.preview(of: paint.mediaID), turns: paint.turns)
                VStack(alignment: .leading, spacing: 6) {
                    MenuField(value: paint.mode.title, entries: {
                        ImageScaleMode.allCases.map { mode in
                            .item(mode.title, checked: mode == paint.mode) { controller.setPictureMode(layer.id, mode) }
                        }
                    }, height: Theme.control)
                    .help("Fill covers the shape, Fit shows the whole picture, Crop places it by hand on the canvas, and Tile repeats it")
                    .rowButton {
                        IconButton(icon: .rotate, help: "Turn the picture a quarter clockwise") { controller.turnPicture(layer.id) }
                    }
                    PanelButton(title: "Replace…") { controller.replaceMedia(of: layer.id) }
                        .help("Choose another picture. The layer keeps its size, its place and its actions.")
                }
            }
            if paint.mode == .tile {
                LabeledRow(label: "Scale") {
                    UnitField(value: paint.tileScale * 100, decimals: 1, suffix: "%", accepts: { $0 > 0 }) { v in
                        edit("Tile Scale") { $0.tileScale = v / 100 }
                    }
                    .help("Each tile's size, as a share of the picture's own")
                }
            }
            LabeledRow(label: "Opacity") {
                UnitField(value: paint.opacity * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    edit("Image Opacity") { $0.opacity = v / 100 }
                }
                .help("Opacity of the picture")
            }
        }
    }

    private func edit(_ name: String, _ change: (inout MotionModel.ImagePaint) -> Void) {
        let edited = PictureEditing.editingPicture(layer, change)
        controller.perform(.batch([.updateLayers([edited])], name: name))
    }
}

/// A picture or a video's first frame, small, the way round it is shown.
struct PictureWell: View {
    let image: CGImage?
    var turns = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl)
        ZStack {
            Checkerboard(cell: Theme.pictureWell / 8)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .rotationEffect(.degrees(Double(turns) * 90))
            }
        }
        .frame(width: Theme.pictureWell, height: Theme.pictureWell)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.edge, lineWidth: 1))
    }
}

/// A video's frames in its box, and Replace.
private struct VideoSection: View {
    let layer: Layer
    let video: VideoContent
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Video") {}
            HStack(alignment: .top, spacing: 8) {
                PictureWell(image: controller.preview(of: video.mediaID))
                VStack(alignment: .leading, spacing: 6) {
                    SegmentRow(selection: video.fit, options: VideoFit.allCases, title: { $0.title }) { fit in
                        controller.edit(layer.id) { l in
                            if case .video(var v) = l.content {
                                v.fit = fit
                                l.content = .video(v)
                            }
                        }
                    }
                    .help("Fill covers the layer's box, cropping what spills over; Fit shows the whole frame inside it")
                    PanelButton(title: "Replace…") { controller.replaceMedia(of: layer.id) }
                        .help("Choose another video. The layer keeps its size, its place and its actions.")
                }
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
    }
}

// MARK: - Stroke

private struct StrokeSection: View {
    let layer: Layer
    let shape: ShapeContent
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    /// Each stroke's settings button, to raise its card beside.
    @State private var settingsFrames: [UUID: CGRect] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Stroke") {
                IconButton(icon: .plus, help: shape.strokes.isEmpty ? "Add a stroke" : "Add a stroke on top") {
                    editShape { s in
                        // Another sits as the top one does, in the stroke colour.
                        var stroke = s.strokes.last?.withNewID() ?? Stroke(paint: .color(LayerFactory.defaultStroke), width: 2)
                        stroke.paint = .color(LayerFactory.defaultStroke)
                        stroke.isEnabled = true
                        s.strokes.append(stroke)
                    }
                }
            }
            // Every stroke, the one drawn on top first (4 October 2026; only
            // the first showed before). Stroke and Trim actions drive the
            // bottom one, the first in the list kept.
            ForEach(Array(shape.strokes.enumerated()).reversed(), id: \.element.id) { index, stroke in
                strokeRows(stroke, index: index)
                    .gridBody()
            }
        }
        .sectionPadding(empty: shape.strokes.isEmpty)
    }

    @ViewBuilder private func strokeRows(_ stroke: Stroke, index i: Int) -> some View {
                VStack(alignment: .leading, spacing: 8) {
                    InspectorItemTitle(icon: .stroke, title: "Stroke") {
                        editShape { s in if s.strokes.indices.contains(i) { s.strokes.remove(at: i) } }
                    }
                    PaintEditor(paint: stroke.paint, isEnabled: stroke.isEnabled, controller: controller, layer: layer,
                                title: "Stroke", slot: .stroke(i),
                                change: { paint in
                                    var l = layer
                                    var s = shape
                                    if s.strokes.indices.contains(i) { s.strokes[i].paint = paint }
                                    l.look = s
                                    return l
                                },
                                toggle: { editShape { s in if s.strokes.indices.contains(i) { s.strokes[i].isEnabled.toggle() } } },
                                showsToggle: true)
                    HStack(spacing: 8) {
                        // An open line has no inside or outside.
                        if shape.geometry.isClosed {
                            MenuField(value: stroke.alignment.rawValue.capitalized, entries: {
                                StrokeAlignment.allCases.map { a in
                                    .item(a.rawValue.capitalized, checked: a == stroke.alignment) {
                                        editShape { s in if s.strokes.indices.contains(i) { s.strokes[i].alignment = a } }
                                    }
                                }
                            }, height: Theme.control)
                            .help("Whether the stroke sits centred on the edge, inside it, or outside it")
                        }
                        UnitField(value: stroke.width, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                            editShape { s in if s.strokes.indices.contains(i) { s.strokes[i].width = v } }
                        }
                        .help("Stroke width")
                    }
                    .rowButton {
                        IconButton(icon: .settings, help: layer.isFrame ? "More stroke settings: ends, corners and dashes"
                                                                        : "More stroke settings: trim, ends, corners and dashes") {
                            // Beside the inspector, towards the canvas, level with the button.
                            let settingsFrame = settingsFrames[stroke.id] ?? .zero
                            let inspectorLeft = settingsFrame.maxX + Theme.panelPad - Theme.panelWidth
                            menus.showPopup(at: CGPoint(x: inspectorLeft - Theme.floatGap - Theme.cardWidth,
                                                        y: settingsFrame.minY - 40)) {
                                PopupCard(title: "Stroke", width: Theme.cardWidth) {
                                    StrokeSettings(layerID: layer.id, strokeID: stroke.id, controller: controller)
                                }
                            }
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { settingsFrames[stroke.id] = $0 }
                    }
                }
    }

    private func editShape(_ change: (inout ShapeContent) -> Void) {
        var s = shape
        change(&s)
        controller.edit(layer.id) { l in l.look = s }
    }
}

/// How a stroke's line is drawn, as its Style row offers.
enum StrokeLine: CaseIterable {
    case solid, dashed, dotted

    var title: String {
        switch self {
        case .solid: "Solid"
        case .dashed: "Dashed"
        case .dotted: "Dotted"
        }
    }

    static func of(_ stroke: Stroke) -> StrokeLine {
        stroke.dotted ? .dotted : stroke.dashPattern.contains(where: { $0 > 0 }) ? .dashed : .solid
    }

    /// Turns `stroke` to this style, keeping its gap where it has one.
    func apply(to stroke: inout Stroke) {
        let gap = stroke.gap > 0 ? stroke.gap : 6
        switch self {
        case .solid:
            stroke.dotted = false
            stroke.dashPattern = []
        case .dashed:
            stroke.dotted = false
            let dash = stroke.dashPattern.first ?? 0
            stroke.dashPattern = [dash > 0 ? dash : 8, gap]
        case .dotted:
            stroke.dotted = true
            stroke.dashPattern = [0, gap]
        }
    }
}

/// The stroke settings that are set once and left: trim, ends, corners and
/// dashes. Raised from the Stroke section's settings button, and reads the
/// layer afresh each time, so it follows every edit while it is up.
private struct StrokeSettings: View {
    let layerID: UUID
    /// Which of the layer's strokes, by id, so it stays the same one as
    /// others are added or removed.
    let strokeID: UUID
    let controller: EditorController

    var body: some View {
        if let layer = controller.project.layer(withID: layerID), let stroke = layer.look?.strokes.first(where: { $0.id == strokeID }) {
            // A frame's stroke has no ends to trim.
            if !layer.isFrame {
                MenuRow(label: "Trim", value: stroke.trim.direction.title, entries: {
                    TrimDirection.allCases.map { d in
                        .item(d.title, checked: d == stroke.trim.direction) { edit { $0.trim.direction = d } }
                    }
                })
                .help("Which way the line is drawn: from its start, from its end, from both ends to meet in the middle, or from the middle out")
                LabeledRow(label: "Drawn") {
                    UnitField(value: stroke.trim.amount * 100, decimals: 1, suffix: "%",
                              accepts: { $0 >= 0 && $0 <= 100 }) { v in
                        edit { $0.trim.amount = v / 100 }
                    }
                }
                .help("How much of the line is drawn. Animate it with a Trim action to draw a line on.")
            }
            titled("Ends") {
                SegmentRow(selection: stroke.cap, options: LineCap.allCases, title: { $0.rawValue.capitalized }) { c in
                    edit { $0.cap = c }
                }
            }
            .help("The ends of open lines and dashes")
            titled("Corners") {
                SegmentRow(selection: stroke.join, options: LineJoin.allCases, title: { $0.rawValue.capitalized }) { j in
                    edit { $0.join = j }
                }
            }
            .help("How the stroke turns a corner")
            titled("Style") {
                SegmentRow(selection: StrokeLine.of(stroke), options: StrokeLine.allCases, title: \.title) { line in
                    edit { line.apply(to: &$0) }
                }
            }
            .help("A solid line, dashes, or round dots")
            switch StrokeLine.of(stroke) {
            case .dashed:
                HStack(spacing: 8) {
                    UnitField(unit: "Dash", value: stroke.dashPattern.first ?? 0, decimals: 1, accepts: { $0 > 0 }) { v in
                        edit { s in s.dashPattern = [v, s.gap] }
                    }
                    UnitField(unit: "Gap", value: stroke.gap, decimals: 1, accepts: { $0 >= 0 }) { v in
                        edit { s in s.dashPattern = [s.dashPattern.first ?? v, v] }
                    }
                }
                .help("Dash and gap lengths in pixels")
            case .dotted:
                UnitField(unit: "Gap", value: stroke.gap, decimals: 1, accepts: { $0 >= 0 }) { v in
                    edit { s in s.dashPattern = [0, v] }
                }
                .help("The space between dots, in pixels")
            case .solid:
                EmptyView()
            }
        }
    }

    private func titled<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            content()
        }
    }

    private func edit(_ change: @escaping (inout Stroke) -> Void) {
        controller.edit(layerID) { l in
            guard var s = l.look, let i = s.strokes.firstIndex(where: { $0.id == strokeID }) else { return }
            change(&s.strokes[i])
            l.look = s
        }
    }
}

// MARK: - Paint

/// A paint's colours: one well for a solid colour, its hex and its
/// opacity; for a gradient, its stops (`GradientStopsEditor`) and the
/// switch for its handles on the canvas.
struct PaintEditor: View {
    let paint: Paint
    let isEnabled: Bool
    let controller: EditorController
    let layer: Layer
    let title: String
    /// Which of the layer's paints this is, for its gradient's handles.
    var slot: PaintSlot? = nil
    /// Builds the whole edited layer for a new paint.
    let change: (Paint) -> Layer
    let toggle: () -> Void
    /// Puts show and hide on the first colour row, in the button column.
    var showsToggle = false

    var body: some View {
        switch paint {
        case .solid(let color):
            colorRow(color, first: true) { c in .solid(c) }
        case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g):
            let editing = controller.editor.gradient.flatMap { $0.layerID == layer.id && $0.slot == slot ? $0 : nil }
            GradientStopsEditor(
                gradient: g, title: title, picked: editing?.stop,
                pick: { stop in
                    if let slot {
                        controller.editor.gradient = GradientEdit(layerID: layer.id, slot: slot, stop: stop)
                        controller.editor.hidesGradient = false
                    }
                },
                edit: GradientCallbacks(
                    commit: { controller.perform(.updateLayers([change(paint.withGradient($0))])) },
                    live: { controller.update([change(paint.withGradient($0))]) },
                    begin: { controller.begin($0) },
                    end: { controller.end() }),
                barButton: {
                    if showsToggle { toggleButton }
                },
                firstRowButton: { EmptyView() })
        case .image:
            // Pictures have their own fields.
            EmptyView()
        }
    }

    @ViewBuilder private func colorRow(_ color: RGBA, first: Bool, _ make: @escaping (RGBA) -> Paint) -> some View {
        if first && showsToggle {
            colorFields(color, make).rowButton { toggleButton }
        } else {
            colorFields(color, make)
        }
    }

    private var toggleButton: some View {
        IconButton(icon: isEnabled ? .eye : .eyeSlash, help: isEnabled ? "Hide the \(title.lowercased())" : "Show the \(title.lowercased())",
                   action: toggle)
    }

    private func colorFields(_ color: RGBA, _ make: @escaping (RGBA) -> Paint) -> some View {
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
        case .angularGradient: return "Angular"
        case .image: return "Image"
        }
    }

    /// The same paint as another kind, carrying its colours across: a solid
    /// becomes a gradient from its colour to transparent, and a gradient
    /// becomes a solid of its first colour. A linear gradient runs across
    /// the middle; a radial or angular one starts from the centre, and
    /// keeps its centre and edge when it turns into the other.
    func converted(to kind: String) -> Paint {
        if case .image = self {
            // A picture has no colour to carry over, so it starts from the
            // default grey.
            return Paint.color(LayerFactory.defaultFill).converted(to: kind)
        }
        guard let target = GradientKind(kindName: kind) else {
            return gradient.map { .color($0.stops.first?.color ?? .white) } ?? self
        }
        var g: MotionModel.Gradient
        if let current = gradient {
            g = current
        } else if case .solid(let c) = self {
            var clear = c
            clear.a = 0
            g = MotionModel.Gradient(stops: [GradientStop(position: 0, color: c), GradientStop(position: 1, color: clear)])
        } else {
            return self
        }
        let centred = { (k: GradientKind?) in k == .radial || k == .angular }
        if gradientKind != target, !(centred(gradientKind) && centred(target)) {
            g.start = target == .linear ? Vec2(0, 0.5) : Vec2(0.5, 0.5)
            g.end = Vec2(1, 0.5)
        }
        return .gradient(g, target)
    }
}

// MARK: - Items

/// The name row over one fill, stroke or effect in a list of them: its
/// icon and name, with its remove button in the button column.
struct InspectorItemTitle: View {
    let icon: Icon
    let title: String
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            IconView(icon, size: 15)
                .foregroundStyle(Theme.textTertiary)
            Text(title)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
        }
        .rowButton { IconButton(icon: .minus, help: "Remove", action: remove) }
    }
}

// MARK: - Effects

/// A mask: the layers in front of it in its group or frame show only
/// where it draws (4 October 2026, as in Figma). Its one control stops it
/// being a mask; Use as Mask is on the layers' right-click menu.
/// A frame in 3D: its children placed in one space and seen through one
/// camera. Off, it is only its header with +; on, its camera and how depth
/// looks, with − in the header.
private struct SpaceSection: View {
    let layer: Layer
    let controller: EditorController

    private enum Camera: Hashable { case perspective, isometric }

    var body: some View {
        let space = layer.space3D
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "3D") {
                if space == nil {
                    IconButton(icon: .plus, help: "Hold the frame's layers in 3D: each sits at its own depth and turns in one space, seen through one camera, the nearest drawn on top") {
                        controller.edit(layer.id) { $0.space3D = Space3D() }
                    }
                } else {
                    IconButton(icon: .minus, help: "Back to flat: the layers are drawn in their own order again, each tilt seen from its own depth") {
                        controller.edit(layer.id) { $0.space3D = nil }
                    }
                }
            }
            if let space { rows(space).gridBody() }
        }
        .sectionPadding(empty: space == nil)
    }

    private func rows(_ space: Space3D) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentRow(selection: space.isIsometric ? Camera.isometric : .perspective, options: [.perspective, .isometric],
                       title: { $0 == .perspective ? "Perspective" : "Isometric" }) { camera in
                edit { $0.isIsometric = camera == .isometric }
            }
            .help("Perspective: nearer is larger. Isometric: seen from infinitely far, nothing grows or shrinks with depth.")
            if !space.isIsometric {
                HStack(spacing: 8) {
                    UnitField(unit: "Distance", value: space.distance, decimals: 0, suffix: "px", accepts: { $0 >= 1 }) { v in
                        edit { $0.distance = v }
                    }
                    .help("How far in front of the frame the camera is. Nearer makes the perspective stronger.")
                }
            }
            // Seen from infinitely far, the camera has no point to look at.
            if !space.isIsometric {
            StackedRow(label: "Vanishing point") {
                UnitField(unit: "X", value: space.vanishingPoint.x * 100, decimals: 0, suffix: "%") { v in
                    edit { $0.vanishingPoint.x = v / 100 }
                }
                .help("Where across the frame the camera looks straight at")
                UnitField(unit: "Y", value: space.vanishingPoint.y * 100, decimals: 0, suffix: "%") { v in
                    edit { $0.vanishingPoint.y = v / 100 }
                }
                .help("Where down the frame the camera looks straight at")
            }
            }
            StackedRow(label: "Orbit") {
                UnitField(unit: "X", value: space.orbit.x, decimals: 1, suffix: "°") { v in edit { $0.orbit.x = v } }
                    .help("Tips the whole space about the frame's middle, the top going away")
                UnitField(unit: "Y", value: space.orbit.y, decimals: 1, suffix: "°") { v in edit { $0.orbit.y = v } }
                    .help("Turns the whole space about the frame's middle, the right going away, as if the camera went round it")
            }
            HStack(spacing: 8) {
                UnitField(unit: "Fade", value: space.depthFade * 100, decimals: 0, suffix: "%",
                          accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    edit { $0.depthFade = v / 100 }
                }
                .help("Depth fade: how much fainter layers grow behind the frame, all of it a frame's length back")
                UnitField(unit: "Blur", value: space.depthBlur, decimals: 1, suffix: "px", accepts: { $0 >= 0 }) { v in
                    edit { $0.depthBlur = v }
                }
                .help("Depth blur: how much blurrier layers grow behind the frame, all of it a frame's length back")
            }
            HStack(spacing: 8) {
                UnitField(unit: "Backs", value: space.backOpacity * 100, decimals: 0, suffix: "%",
                          accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    edit { $0.backOpacity = v / 100 }
                }
                .help("How strongly a layer shows with its back to the camera: 100% whole, 0% hidden")
                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            }
        }
    }

    private func edit(_ change: @escaping (inout Space3D) -> Void) {
        controller.edit(layer.id) { l in
            guard var space = l.space3D else { return }
            change(&space)
            l.space3D = space
        }
    }
}

private struct MaskSection: View {
    let layer: Layer
    let controller: EditorController

    var body: some View {
        HeaderRow(title: "Mask") {
            IconButton(icon: .minus, help: "Remove the mask: this layer draws again, and the layers in front of it show whole") {
                controller.removeMask(layer.id)
            }
        }
        .sectionPadding(empty: true)
    }
}

private struct EffectsSection: View {
    let layer: Layer
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var addFrame: CGRect = .zero
    /// Skew and Tilt show once they are set, or once added from the menu
    /// while still at zero, until another layer is picked.
    @State private var addedSkew = false
    @State private var addedTilt = false
    @State private var addedBend = false

    private var t: Transform { layer.transform }
    /// Sound is never drawn, so it cannot slant or turn.
    private var canWarp: Bool {
        if case .audio = layer.content { return false }
        return true
    }
    private var showsSkew: Bool { canWarp && (addedSkew || t.skew != .zero) }
    private var showsTilt: Bool { canWarp && (addedTilt || t.tilt.isTilted) }
    private var showsBend: Bool { canWarp && (addedBend || t.bend != .zero) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Effects") {
                IconButton(icon: .plus, help: "Add a shadow, a blur, a skew, a tilt or a bend") {
                    var entries: [MenuEntry] = [.item("Drop Shadow", icon: .shadow) { add(.dropShadow(DropShadow())) }]
                    // These follow a shape's outline, so only shapes and
                    // frames have them.
                    if layer.look != nil {
                        entries.append(.item("Inner Shadow", icon: .innerShadow) { add(.innerShadow(DropShadow(offset: Vec2(0, 4), blur: 4))) })
                    }
                    entries.append(.item("Layer Blur", icon: .layerBlur) { add(.layerBlur(LayerBlur())) })
                    if layer.look != nil {
                        entries.append(.item("Background Blur", icon: .backgroundBlur) { add(.backgroundBlur(BackgroundBlur())) })
                    }
                    if canWarp && !(showsSkew && showsTilt && showsBend) {
                        entries.append(.separator)
                        if !showsSkew { entries.append(.item("Skew", icon: .skew) { addedSkew = true }) }
                        if !showsTilt { entries.append(.item("Tilt", icon: .tilt) { addedTilt = true }) }
                        if !showsBend { entries.append(.item("Bend", icon: .bend) { addedBend = true }) }
                    }
                    menus.show(entries, at: CGPoint(x: addFrame.maxX - Theme.menuMinWidth, y: addFrame.maxY + 4))
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { addFrame = $0 }
            }
            ForEach(Array(layer.effects.enumerated()), id: \.element.id) { index, effect in
                effectRows(effect, index: index)
                    .gridBody()
            }
            if showsSkew { skewRows.gridBody() }
            if showsTilt { tiltRows.gridBody() }
            if showsBend { bendRows.gridBody() }
        }
        .sectionPadding(empty: layer.effects.isEmpty && !showsSkew && !showsTilt && !showsBend)
    }

    private func titleRow(_ icon: Icon, _ title: String, remove: @escaping () -> Void) -> some View {
        InspectorItemTitle(icon: icon, title: title, remove: remove)
    }

    /// Show and hide, on an effect's first row of values.
    private func eyeButton(_ effect: Effect, _ index: Int) -> some View {
        IconButton(icon: effect.isEnabled ? .eye : .eyeSlash, help: effect.isEnabled ? "Hide" : "Show") {
            edit(index) { $0.isEnabled.toggle() }
        }
    }

    private var skewRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(.skew, "Skew") {
                addedSkew = false
                controller.edit(layer.id) { l in l.transform.skew = .zero }
            }
            HStack(spacing: 8) {
                UnitField(unit: "X", value: t.skew.x, decimals: 1, suffix: "°") { v in
                    controller.edit(layer.id) { l in l.transform.skew.x = v }
                }
                .help("Slants its sides, so the bottom moves across")
                UnitField(unit: "Y", value: t.skew.y, decimals: 1, suffix: "°") { v in
                    controller.edit(layer.id) { l in l.transform.skew.y = v }
                }
                .help("Slants its top and bottom, so the right side moves down")
            }
        }
    }

    private var bendRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(.bend, "Bend") {
                addedBend = false
                controller.edit(layer.id) { l in l.transform.bend = .zero }
            }
            HStack(spacing: 8) {
                UnitField(unit: "X", value: t.bend.x, decimals: 1, suffix: "°") { v in
                    controller.edit(layer.id) { l in l.transform.bend.x = v }
                }
                .help("Curves it round an upright line, its width that much of a turn: positive brings the middle forward, negative hollows it")
                UnitField(unit: "Y", value: t.bend.y, decimals: 1, suffix: "°") { v in
                    controller.edit(layer.id) { l in l.transform.bend.y = v }
                }
                .help("Curves it round a level line, its height that much of a turn: positive brings the middle forward, negative hollows it")
            }
        }
    }

    private var tiltRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(.tilt, "Tilt") {
                addedTilt = false
                controller.edit(layer.id) { l in l.transform.tilt = .none }
            }
            HStack(spacing: 8) {
                UnitField(unit: "X", value: t.tilt.x, decimals: 1, suffix: "°") { v in
                    controller.edit(layer.id) { l in l.transform.tilt.x = v }
                }
                .help("Tips it back in perspective around a level line through its anchor, the top going away")
                UnitField(unit: "Y", value: t.tilt.y, decimals: 1, suffix: "°") { v in
                    controller.edit(layer.id) { l in l.transform.tilt.y = v }
                }
                .help("Turns it in perspective around an upright line through its anchor, the right side going away")
            }
            // Depth only matters once it is tilted, and not in a frame in
            // 3D, whose camera it is seen through.
            if t.tilt.isTilted, controller.project.space3D(holding: layer.id) == nil {
                UnitField(unit: "Depth", value: t.tilt.depth, decimals: 0, suffix: "px", accepts: { $0 > 1 }) { v in
                    controller.edit(layer.id) { l in l.transform.tilt.depth = v }
                }
                .help("How far away it is seen from. Nearer makes the perspective stronger.")
            }
        }
    }

    @ViewBuilder private func effectRows(_ effect: Effect, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow(effect.icon, effect.title) {
                controller.edit(layer.id) { l in l.effects.remove(at: index) }
            }
            switch effect.kind {
            case .dropShadow(let s), .innerShadow(let s):
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
                .rowButton { eyeButton(effect, index) }
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
                .rowButton { eyeButton(effect, index) }
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
                .rowButton { eyeButton(effect, index) }
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

    /// The layer with the drop or inner shadow at `index` changed.
    private func withShadow(_ index: Int, _ change: (inout DropShadow) -> Void) -> Layer {
        var l = layer
        guard l.effects.indices.contains(index) else { return l }
        switch l.effects[index].kind {
        case .dropShadow(var s):
            change(&s)
            l.effects[index].kind = .dropShadow(s)
        case .innerShadow(var s):
            change(&s)
            l.effects[index].kind = .innerShadow(s)
        default:
            break
        }
        return l
    }
}

extension Effect {
    var title: String {
        switch kind {
        case .dropShadow: return "Drop Shadow"
        case .innerShadow: return "Inner Shadow"
        case .layerBlur: return "Layer Blur"
        case .backgroundBlur: return "Background Blur"
        }
    }

    /// The same drawings as the actions that animate each one.
    var icon: Icon {
        switch kind {
        case .dropShadow: return .shadow
        case .innerShadow: return .innerShadow
        case .layerBlur: return .layerBlur
        case .backgroundBlur: return .backgroundBlur
        }
    }
}
