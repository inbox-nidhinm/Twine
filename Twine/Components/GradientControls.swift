import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import Theme

/// Changes to a gradient: `commit` is one finished change; a drag on the
/// bar or in a colour picker is `live` changes between `begin` and `end`,
/// which undo as one step.
struct GradientCallbacks {
    var commit: (MotionModel.Gradient) -> Void
    var live: (MotionModel.Gradient) -> Void
    var begin: (String) -> Void
    var end: () -> Void
}

/// A gradient's stops, as Figma shows them (4 October 2026): a bar of the
/// gradient with a marker for each stop, where a click adds a stop in the
/// colour already there and a marker drags along, beside the picked stop's
/// place; then a row for each stop from the start to the end, with its
/// colour, hex and opacity, as a solid colour's row, and a remove button
/// while there are more than two. (A place on every row left the hex no
/// room in the panel.) Editing a stop's colour picks it.
struct GradientStopsEditor<BarButton: View, FirstRowButton: View>: View {
    let gradient: MotionModel.Gradient
    var title = "Colour"
    /// The stop picked on the bar or the canvas.
    let picked: Int?
    let pick: (Int?) -> Void
    let edit: GradientCallbacks
    /// Beside the bar, in the button column.
    @ViewBuilder var barButton: () -> BarButton
    /// Beside the first stop, when it has no remove button.
    @ViewBuilder var firstRowButton: () -> FirstRowButton

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                GradientBar(gradient: gradient, picked: picked, pick: pick, edit: edit)
                if let picked, gradient.stops.indices.contains(picked) {
                    UnitField(value: gradient.stops[picked].position * 100, decimals: 0, suffix: "%",
                              accepts: { $0 >= 0 && $0 <= 100 }) { v in
                        edit.commit(GradientEditing.moving(picked, in: gradient, to: v / 100))
                    }
                    .frame(width: Theme.stopField)
                    .help("Where the picked stop sits, from the start of the gradient to its end")
                }
            }
            .rowButton(barButton)
            let order = GradientEditing.order(of: gradient)
            ForEach(Array(order.enumerated()), id: \.element) { place, index in
                stopRow(index)
                    .rowButton {
                        if gradient.stops.count > GradientEditing.fewestStops {
                            IconButton(icon: .minus, help: "Remove this stop") {
                                guard let fewer = GradientEditing.removing(index, from: gradient) else { return }
                                pick(nil)
                                edit.commit(fewer)
                            }
                        } else if place == 0 {
                            firstRowButton()
                        }
                    }
            }
        }
    }

    private func stopRow(_ index: Int) -> some View {
        let stop = gradient.stops[index]
        func recoloured(_ c: RGBA) -> MotionModel.Gradient {
            var g = gradient
            g.stops[index].color = c
            return g
        }
        return HStack(spacing: 6) {
            ColorWell(color: stop.color, size: Theme.control, title: title,
                      onChange: { edit.live(recoloured($0)) },
                      onBegin: { pick(index); edit.begin("Colour") }, onEnd: edit.end)
            HexField(color: stop.color) { c in
                pick(index)
                edit.commit(recoloured(c))
            }
            UnitField(value: stop.color.a * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                var c = stop.color
                c.a = v / 100
                pick(index)
                edit.commit(recoloured(c))
            }
            .frame(width: Theme.labelWidth)
            .help("Opacity of this stop")
        }
    }
}

extension GradientStopsEditor where FirstRowButton == EmptyView {
    init(gradient: MotionModel.Gradient, title: String = "Colour", picked: Int?, pick: @escaping (Int?) -> Void,
         edit: GradientCallbacks, @ViewBuilder barButton: @escaping () -> BarButton) {
        self.init(gradient: gradient, title: title, picked: picked, pick: pick, edit: edit,
                  barButton: barButton, firstRowButton: { EmptyView() })
    }
}

/// The gradient drawn left to right over the transparency pattern, with a
/// marker for each stop. A press on a marker picks it and a drag moves it;
/// a press anywhere else adds a stop there.
private struct GradientBar: View {
    let gradient: MotionModel.Gradient
    let picked: Int?
    let pick: (Int?) -> Void
    let edit: GradientCallbacks

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl)
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Checkerboard(cell: Theme.control / 4)
                LinearGradient(stops: gradient.swiftUIStops, startPoint: .leading, endPoint: .trailing)
                // The picked marker last, over the others.
                ForEach(markerOrder, id: \.self) { index in
                    marker(index)
                        .position(x: GradientBarCatcher.x(of: gradient.stops[index].position, width: width),
                                  y: Theme.control / 2)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.edge, lineWidth: 1))
            .overlay(GradientBarCatcher(positions: gradient.stops.map(\.position), picked: picked, press: press,
                                        drag: drag, release: release))
        }
        .frame(height: Theme.control)
    }

    private var markerOrder: [Int] {
        gradient.stops.indices.filter { $0 != picked } + (picked.map { gradient.stops.indices.contains($0) ? [$0] : [] } ?? [])
    }

    private func marker(_ index: Int) -> some View {
        let isPicked = index == picked
        let height = isPicked ? Theme.gradientMarkerPicked : Theme.gradientMarker
        let shape = RoundedRectangle(cornerRadius: Theme.radiusSwatchMark)
        return ZStack {
            Checkerboard(cell: Theme.gradientMarker / 4)
            gradient.stops[index].color.color
        }
        .frame(width: Theme.gradientMarker, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.textPrimary, lineWidth: isPicked ? 2 : 1.5))
        .shadow(color: Theme.shadow, radius: 1.5)
    }

    /// The stop under the press, or a new one where it landed.
    private func press(_ index: Int?, at position: Double) {
        if let index {
            pick(index)
        } else {
            let added = GradientEditing.adding(to: gradient, at: position)
            edit.commit(added.gradient)
            pick(added.index)
        }
    }

    private func drag(_ index: Int, to position: Double, began: Bool) {
        if !began { edit.begin("Move Stop") }
        edit.live(GradientEditing.moving(index, in: gradient, to: position))
    }

    private func release(_ began: Bool) {
        if began { edit.end() }
    }
}

/// The bar's presses, an AppKit view so every press lands, as the number
/// fields' `ScrubSurface` is.
private struct GradientBarCatcher: NSViewRepresentable {
    let positions: [Double]
    let picked: Int?
    let press: (Int?, Double) -> Void
    let drag: (Int, Double, Bool) -> Void
    let release: (Bool) -> Void

    /// Where a stop at `position` sits across a bar `width` wide: markers
    /// at the ends stay inside it.
    static func x(of position: Double, width: CGFloat) -> CGFloat {
        let inset = Theme.gradientMarker / 2 + 1
        return inset + CGFloat(position) * max(width - inset * 2, 1)
    }

    static func position(of x: CGFloat, width: CGFloat) -> Double {
        let inset = Theme.gradientMarker / 2 + 1
        return min(max(Double((x - inset) / max(width - inset * 2, 1)), 0), 1)
    }

    func makeNSView(context: Context) -> GradientBarView { GradientBarView() }

    func updateNSView(_ view: GradientBarView, context: Context) { view.catcher = self }
}

private final class GradientBarView: NSView {
    var catcher: GradientBarCatcher?
    private var dragging: Int?
    private var began = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isFlipped: Bool { true }

    private func x(_ event: NSEvent) -> CGFloat { convert(event.locationInWindow, from: nil).x }

    /// The marker under `x`, the picked one first where they overlap.
    private func marker(at x: CGFloat) -> Int? {
        guard let catcher else { return nil }
        let reach = Theme.gradientMarker / 2 + 2
        let near = catcher.positions.indices.filter {
            abs(GradientBarCatcher.x(of: catcher.positions[$0], width: bounds.width) - x) <= reach
        }
        if let picked = catcher.picked, near.contains(picked) { return picked }
        return near.min { abs(GradientBarCatcher.x(of: catcher.positions[$0], width: bounds.width) - x)
            < abs(GradientBarCatcher.x(of: catcher.positions[$1], width: bounds.width) - x) }
    }

    override func mouseDown(with event: NSEvent) {
        guard let catcher else { return }
        let x = x(event)
        let hit = marker(at: x)
        began = false
        // A new stop is picked as it is added; dragging on moves it.
        dragging = hit ?? catcher.positions.count
        catcher.press(hit, GradientBarCatcher.position(of: x, width: bounds.width))
    }

    override func mouseDragged(with event: NSEvent) {
        guard let catcher, let index = dragging else { return }
        catcher.drag(index, GradientBarCatcher.position(of: x(event), width: bounds.width), began)
        began = true
    }

    override func mouseUp(with event: NSEvent) {
        catcher?.release(began)
        dragging = nil
        began = false
    }
}

extension Paint {
    /// The gradient a linear or radial paint draws.
    var gradient: MotionModel.Gradient? {
        switch self {
        case .linearGradient(let g), .radialGradient(let g): g
        default: nil
        }
    }

    var isRadial: Bool {
        if case .radialGradient = self { return true }
        return false
    }
}

extension Layer {
    /// The paint in `slot`, if the layer has one there.
    func paint(at slot: PaintSlot) -> Paint? {
        guard let look else { return nil }
        switch slot {
        case .fill(let i): return look.fills.indices.contains(i) ? look.fills[i].paint : nil
        case .stroke(let i): return look.strokes.indices.contains(i) ? look.strokes[i].paint : nil
        }
    }

    /// The layer with `paint` in `slot`.
    func with(_ paint: Paint, at slot: PaintSlot) -> Layer {
        guard var look else { return self }
        switch slot {
        case .fill(let i) where look.fills.indices.contains(i): look.fills[i].paint = paint
        case .stroke(let i) where look.strokes.indices.contains(i): look.strokes[i].paint = paint
        default: return self
        }
        var l = self
        l.look = look
        return l
    }
}
