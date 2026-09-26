import SwiftUI
import MotionModel
import Theme

/// Callbacks for a value edited in two ways: typed, as one finished change,
/// or dragged in a colour picker, as a run of live changes between a begin
/// and an end that undo as one step.
struct EditCallbacks<Value> {
    var commit: (Value) -> Void
    var live: (Value) -> Void
    var begin: () -> Void
    var end: () -> Void
}

/// A paint's kind (Solid, Linear, Radial) and its colours, each as a well,
/// its hex and its opacity.
struct PaintControls: View {
    let paint: Paint
    var title = "Colour"
    let edit: EditCallbacks<Paint>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SegmentRow(selection: paint.kindName, options: ["Solid", "Linear", "Radial"], title: { $0 }) { kind in
                edit.commit(paint.converted(to: kind))
            }
            switch paint {
            case .solid(let color):
                colorRow(color) { .solid($0) }
            case .linearGradient(let g), .radialGradient(let g):
                ForEach(Array(g.stops.enumerated()), id: \.offset) { index, stop in
                    colorRow(stop.color) { c in
                        var gradient = g
                        gradient.stops[index].color = c
                        return paint.withGradient(gradient)
                    }
                }
            }
        }
    }

    private func colorRow(_ color: RGBA, _ make: @escaping (RGBA) -> Paint) -> some View {
        ColorRow(color: color, title: title, edit: EditCallbacks(
            commit: { edit.commit(make($0)) }, live: { edit.live(make($0)) }, begin: edit.begin, end: edit.end))
    }
}

/// One colour: a well that opens the picker, its hex, and its opacity.
struct ColorRow: View {
    let color: RGBA
    var title = "Colour"
    let edit: EditCallbacks<RGBA>

    var body: some View {
        HStack(spacing: 6) {
            ColorWell(color: color, size: Theme.control, title: title,
                      onChange: edit.live, onBegin: edit.begin, onEnd: edit.end)
            HexField(color: color) { edit.commit($0) }
            UnitField(value: color.a * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                var c = color
                c.a = v / 100
                edit.commit(c)
            }
            .frame(width: Theme.labelWidth)
            .help("Opacity of this colour")
        }
    }
}

/// A shadow's colour and opacity, offset, blur and spread.
struct ShadowControls: View {
    let shadow: DropShadow
    let edit: EditCallbacks<DropShadow>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ColorWell(color: shadow.color, size: Theme.control, title: "Shadow",
                          onChange: { c in edit.live(with { $0.color = c }) }, onBegin: edit.begin, onEnd: edit.end)
                HexField(color: shadow.color) { c in edit.commit(with { $0.color = c }) }
                UnitField(value: shadow.opacity * 100, decimals: 0, suffix: "%", accepts: { $0 >= 0 && $0 <= 100 }) { v in
                    edit.commit(with { $0.opacity = v / 100 })
                }
                .frame(width: Theme.labelWidth)
                .help("Shadow opacity")
            }
            HStack(spacing: 8) {
                UnitField(unit: "X", value: shadow.offset.x, decimals: 1) { v in edit.commit(with { $0.offset.x = v }) }
                UnitField(unit: "Y", value: shadow.offset.y, decimals: 1) { v in edit.commit(with { $0.offset.y = v }) }
            }
            HStack(spacing: 8) {
                UnitField(unit: "Blur", value: shadow.blur, decimals: 1, accepts: { $0 >= 0 }) { v in
                    edit.commit(with { $0.blur = v })
                }
                UnitField(unit: "Spread", value: shadow.spread, decimals: 1) { v in edit.commit(with { $0.spread = v }) }
                    .help("Grows the shadow past the shape before it is blurred, or shrinks it with a negative number. Shapes only.")
            }
        }
    }

    private func with(_ change: (inout DropShadow) -> Void) -> DropShadow {
        var s = shadow
        change(&s)
        return s
    }
}

/// A small picture of a paint, over the transparency pattern.
struct PaintSwatch: View {
    let paint: Paint
    var size: CGFloat = Theme.control

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusControl)
        ZStack {
            Checkerboard(cell: size / 4)
            switch paint {
            case .solid(let color):
                color.color
            case .linearGradient(let g):
                LinearGradient(stops: g.swiftUIStops, startPoint: UnitPoint(x: g.start.x, y: g.start.y),
                               endPoint: UnitPoint(x: g.end.x, y: g.end.y))
            case .radialGradient(let g):
                RadialGradient(stops: g.swiftUIStops, center: UnitPoint(x: g.start.x, y: g.start.y),
                               startRadius: 0, endRadius: size * hypot(g.end.x - g.start.x, g.end.y - g.start.y))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.edge, lineWidth: 1))
    }
}

extension MotionModel.Gradient {
    var swiftUIStops: [SwiftUI.Gradient.Stop] {
        stops.sorted { $0.position < $1.position }.map { SwiftUI.Gradient.Stop(color: $0.color.color, location: $0.position) }
    }
}
