import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// One of a layer's fills or strokes, by its id, so a row and its card stay
/// on the same one as others are added or removed.
enum PaintTarget: Equatable {
    case fill(UUID)
    case stroke(UUID)

    var title: String {
        switch self {
        case .fill: "Fill"
        case .stroke: "Stroke"
        }
    }
}

extension Layer {
    /// Where the target's paint is among the layer's paints now.
    func slot(_ target: PaintTarget) -> PaintSlot? {
        switch target {
        case .fill(let id): look?.fills.firstIndex { $0.id == id }.map { .fill($0) }
        case .stroke(let id): look?.strokes.firstIndex { $0.id == id }.map { .stroke($0) }
        }
    }
}

/// A fill or a stroke's paint on one row, as Figma shows it (26 November
/// 2026): its swatch, which raises the card where its kind and colours are
/// set; a solid colour's hex and opacity, a gradient's kind, or a picture's
/// opacity; show and hide; and remove in the button column.
struct PaintRow: View {
    let layer: Layer
    let target: PaintTarget
    let paint: Paint
    let isEnabled: Bool
    let controller: EditorController
    /// Other selected layers with the same paints: the paint in the same
    /// place of each changes with this one.
    var others: [UUID] = []
    let toggle: () -> Void
    let remove: () -> Void

    @Environment(MenuHost.self) private var menus
    @Environment(\.documentColors) private var documentColors
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    private var name: String { target.title.lowercased() }

    var body: some View {
        HStack(spacing: Theme.space6) {
            Button(action: open) { swatch }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                .help("Solid colour, gradient or picture")
                .accessibilityLabel(target.title)
            fields
                .opacity(isEnabled ? 1 : 0.5)
            IconButton(icon: isEnabled ? .eye : .eyeSlash, help: isEnabled ? "Hide the \(name)" : "Show the \(name)",
                       action: toggle)
        }
        .rowButton { IconButton(icon: .minus, help: "Remove the \(name)", action: remove) }
    }

    @ViewBuilder private var swatch: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl)
        if let picture = paint.imagePaint, let image = controller.preview(of: picture.mediaID) {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: Theme.control, height: Theme.control)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Theme.edge, lineWidth: Theme.hairline))
        } else {
            PaintSwatch(paint: paint)
        }
    }

    @ViewBuilder private var fields: some View {
        if case .solid(let color) = paint {
            JoinedFields {
                HexField(color: color, corner: 0, showsHash: false) { commit(.solid($0)) }
                    .help("The colour as six hex digits")
                UnitField(corner: 0, value: color.a * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    var c = color
                    c.a = v / 100
                    commit(.solid(c))
                }
                .frame(width: Theme.paintOpacity)
                .help("Opacity of this colour")
            }
        } else if let picture = paint.imagePaint {
            JoinedFields {
                kindButton
                UnitField(corner: 0, value: picture.opacity * 100, decimals: 0, suffix: "%",
                          accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    guard let fresh = controller.project.layer(withID: layer.id) else { return }
                    let edited = PictureEditing.editingPicture(fresh) { $0.opacity = v / 100 }
                    controller.perform(.batch([.updateLayers([edited])], name: "Image Opacity"))
                }
                .frame(width: Theme.paintOpacity)
                .help("Opacity of the picture")
            }
        } else {
            kindButton
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        }
    }

    /// A gradient's or a picture's kind, where a colour has its hex: a
    /// button that raises the card, as the swatch does.
    private var kindButton: some View {
        Button(action: open) {
            Text(paint.kindName)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, Theme.space8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: Theme.control)
                .background(hovering ? Theme.panelHover : Theme.panelRaised)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Change the gradient or the picture")
    }

    /// One finished change, made to the layer as it is in the project now.
    private func commit(_ paint: Paint) {
        guard let fresh = controller.project.layer(withID: layer.id), let slot = fresh.slot(target) else { return }
        controller.perform(.updateLayers(controller.painted(paint, at: slot, of: fresh, and: others)))
    }

    private func open() {
        let id = layer.id
        let target = target
        // Working on a gradient brings back its line on the canvas.
        if paint.gradient != nil, let slot = layer.slot(target) {
            controller.editor.hidesGradient = false
            if controller.editor.gradient?.layerID != id || controller.editor.gradient?.slot != slot {
                controller.editor.gradient = GradientEdit(layerID: id, slot: slot)
            }
        }
        let swatches = documentColors()
        // Beside the swatch, towards the canvas, level with it. A gradient's
        // card stays up while its line is dragged on the canvas.
        menus.showPopup(at: CGPoint(x: frame.minX - Theme.cardWidth - Theme.floatGap * 2, y: frame.minY - 40),
                        staysOverCanvas: { [weak controller] in
                            guard let layer = controller?.project.layer(withID: id), let slot = layer.slot(target) else { return false }
                            return layer.paint(at: slot)?.gradient != nil
                        }) {
            PaintCard(layerID: id, target: target, swatches: swatches, controller: controller, others: others)
        }
    }
}

/// The card a fill's or a stroke's swatch raises: the kind of paint along
/// its top (Solid, Linear, Radial, Angular, and for a fill, Image), then
/// that kind's own controls. A colour has the picker; a gradient its bar
/// of stops over the picker for the picked stop; a picture its mode, turn
/// and Replace. It reads the layer afresh, so it follows every edit.
struct PaintCard: View {
    let layerID: UUID
    let target: PaintTarget
    let swatches: [RGBA]
    let controller: EditorController
    /// Other selected layers whose paint in the same place changes too.
    var others: [UUID] = []

    @Environment(MenuHost.self) private var menus

    private var current: (layer: Layer, slot: PaintSlot, paint: Paint)? {
        guard let layer = controller.project.layer(withID: layerID), let slot = layer.slot(target),
              let paint = layer.paint(at: slot) else { return nil }
        return (layer, slot, paint)
    }

    var body: some View {
        let now = current
        PopupCard(title: target.title, width: Theme.cardWidth) {
            if let now {
                SegmentRow(selection: now.paint.kindName, options: kinds(now.layer, now.slot), title: { $0 },
                           icon: Icon.fillKind) { setKind($0) }
                controls(now.layer, now.paint)
                    .padding(.top, Theme.space4)
            }
        }
        // Gone with its paint, or when its layer is no longer the selection.
        .onChange(of: now == nil) { _, gone in if gone { menus.dismiss() } }
        .onChange(of: controller.selection) { _, selection in if !selection.contains(layerID) { menus.dismiss() } }
    }

    /// One picture fill a layer: Image is offered where it is, or on any
    /// fill while there is none. A stroke has no picture, and several
    /// layers do not take one together.
    private func kinds(_ layer: Layer, _ slot: PaintSlot) -> [String] {
        var kinds = ["Solid", "Linear", "Radial", "Angular"]
        if case .fill(let i) = slot, others.isEmpty {
            let picture = layer.look?.pictureIndex
            if picture == nil || picture == i { kinds.append("Image") }
        }
        return kinds
    }

    @ViewBuilder private func controls(_ layer: Layer, _ paint: Paint) -> some View {
        if case .solid(let color) = paint {
            ColorPicker(color: color, documentColors: swatches,
                        onChange: { live(.solid($0)) },
                        onBegin: { controller.begin("Colour") },
                        onEnd: { controller.end() })
        } else if let gradient = paint.gradient {
            let picked = pickedStop(in: gradient)
            HStack(spacing: Theme.space6) {
                GradientBar(gradient: gradient, picked: picked, pick: pick, edit: gradientEdits)
                UnitField(value: gradient.stops[picked].position * 100, decimals: 0, suffix: "%",
                          accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    setGradient { GradientEditing.moving(picked, in: $0, to: v / 100) }
                }
                .frame(width: Theme.stopField)
                .help("Where the picked stop sits, from the start of the gradient to its end")
                IconButton(icon: .minus, help: "Remove the picked stop") {
                    guard let now = current?.paint.gradient, let fewer = GradientEditing.removing(picked, from: now) else { return }
                    pick(nil)
                    commit { $0.withGradient(fewer) }
                }
                .disabled(gradient.stops.count <= GradientEditing.fewestStops)
            }
            // A picker of its own for each stop, so it starts from that
            // stop's colour.
            ColorPicker(color: gradient.stops[picked].color, documentColors: swatches,
                        onChange: { c in live { $0.recolouring(picked, c) } },
                        onBegin: {
                            pick(picked)
                            controller.begin("Colour")
                        },
                        onEnd: { controller.end() })
                .id(picked)
        } else if let picture = paint.imagePaint {
            // Its rows keep a button column, as in the inspector.
            PictureFields(layer: layer, paint: picture, controller: controller)
                .padding(.trailing, Theme.rowGutter)
        }
    }

    // MARK: Gradients

    /// The stop picked on the bar or the canvas, or the first along the
    /// gradient while none is.
    private func pickedStop(in gradient: MotionModel.Gradient) -> Int {
        if let edit = controller.editor.gradient, edit.layerID == layerID, edit.slot == current?.slot,
           let stop = edit.stop, gradient.stops.indices.contains(stop) {
            return stop
        }
        return GradientEditing.order(of: gradient).first ?? 0
    }

    private func pick(_ stop: Int?) {
        guard let slot = current?.slot else { return }
        controller.editor.gradient = GradientEdit(layerID: layerID, slot: slot, stop: stop)
        controller.editor.hidesGradient = false
    }

    private var gradientEdits: GradientCallbacks {
        GradientCallbacks(commit: { g in commit { $0.withGradient(g) } },
                          live: { g in live { $0.withGradient(g) } },
                          begin: { controller.begin($0) },
                          end: { controller.end() })
    }

    private func setGradient(_ change: (MotionModel.Gradient) -> MotionModel.Gradient) {
        commit { paint in paint.gradient.map { paint.withGradient(change($0)) } ?? paint }
    }

    // MARK: Changes

    private func setKind(_ kind: String) {
        guard let now = current else { return }
        if kind == "Image" {
            if !now.paint.isImage, case .fill(let i) = now.slot { controller.fillWithPicture(layerID, at: i) }
            return
        }
        commit { $0.converted(to: kind) }
        controller.editor.hidesGradient = false
        if kind != "Solid" { controller.editor.gradient = GradientEdit(layerID: layerID, slot: now.slot) }
    }

    /// One finished change to the paint as it is in the project now.
    private func commit(_ change: (Paint) -> Paint) {
        guard let now = current else { return }
        controller.perform(.updateLayers(controller.painted(change(now.paint), at: now.slot, of: now.layer, and: others)))
    }

    /// A step of a drag, between `begin` and `end`.
    private func live(_ change: (Paint) -> Paint) {
        guard let now = current else { return }
        controller.update(controller.painted(change(now.paint), at: now.slot, of: now.layer, and: others))
    }

    private func live(_ paint: Paint) { live { _ in paint } }
}

private extension Paint {
    /// The gradient with one stop in another colour; any other paint as it is.
    func recolouring(_ stop: Int, _ color: RGBA) -> Paint {
        guard var g = gradient, g.stops.indices.contains(stop) else { return self }
        g.stops[stop].color = color
        return withGradient(g)
    }
}

extension EditorController {
    /// `layer` with a paint in one of its places, and with it each of the
    /// `others` that has a paint in that place, as they are in the project now.
    func painted(_ paint: Paint, at slot: PaintSlot, of layer: Layer, and others: [UUID]) -> [Layer] {
        [layer.with(paint, at: slot)] + freshLayers(others).compactMap { other in
            other.paint(at: slot) == nil ? nil : other.with(paint, at: slot)
        }
    }
}
