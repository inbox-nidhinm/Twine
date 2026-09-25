import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// Shown while keyframes are selected in the timeline: how the segments that
/// start at them move. Changing the easing changes it for every selected
/// keyframe at once.
struct KeyframeInspector: View {
    let controller: EditorController
    let refs: Set<KeyframeRef>

    private var easings: [Easing] {
        refs.compactMap { ref in
            guard let layer = controller.project.layer(withID: ref.layerID) else { return nil }
            return LayerProperties.get(ref.property, of: layer)?.marks.first { $0.id == ref.keyframeID }?.easing
        }
    }

    /// The easing they share, or nil when they differ.
    private var shared: Easing? {
        let all = easings
        guard let first = all.first, all.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Easing shapes the move from a keyframe to the next one, so a
    /// property's last keyframe has nothing to ease.
    private var anyEases: Bool {
        refs.contains { ref in
            guard let layer = controller.project.layer(withID: ref.layerID),
                  let marks = LayerProperties.get(ref.property, of: layer)?.marks,
                  let mark = marks.first(where: { $0.id == ref.keyframeID }) else { return false }
            return marks.contains { $0.time > mark.time }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: refs.count == 1 ? "Keyframe" : "Keyframes") {}
            VStack(alignment: .leading, spacing: 10) {
                if refs.count == 1, let ref = refs.first { timeField(ref) }
                MenuRow(label: "Easing", value: anyEases ? shared.map(Self.name) ?? "Mixed" : "None",
                        entries: entries, isEnabled: anyEases)
                    .help(anyEases
                          ? "How the move from this keyframe to the next one speeds up and slows down."
                          : "Easing shapes the move from a keyframe to the next one, and nothing comes after the last keyframe. Select the keyframe before it.")
                switch anyEases ? shared : nil {
                case .bezier(let curve):
                    CurveEditor(curve: curve, controller: controller)
                        .frame(height: 150)
                case .spring(let spring):
                    SpringEditor(spring: spring, controller: controller)
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, Theme.panelPad)
        }
        .padding(.bottom, Theme.panelPad)
    }

    private func timeField(_ ref: KeyframeRef) -> some View {
        let layer = controller.project.layer(withID: ref.layerID)
        let time = layer.flatMap { LayerProperties.get(ref.property, of: $0)?.marks.first { $0.id == ref.keyframeID }?.time } ?? 0
        let frames = controller.editor.showsFrames
        let rate = controller.frameRate
        return LabeledRow(label: "Time") {
            UnitField(value: frames ? Double(rate.frame(at: time)) : time, decimals: frames ? 0 : 3,
                      suffix: frames ? "f" : "s", accepts: { $0 >= 0 }) { v in
                guard let layer else { return }
                let t = rate.snapped(frames ? rate.time(ofFrame: Int(v.rounded())) : v)
                controller.perform(.batch([.updateLayers([Keyframing.retime([ref: t], in: layer)])], name: "Move Keyframe"))
            }
        }
    }

    private func entries() -> [MenuEntry] {
        var list: [MenuEntry] = [
            .item("Linear", checked: shared == .linear) { controller.setEasing(.linear) },
            .item("Hold", checked: shared == .hold) { controller.setEasing(.hold) },
            .separator,
        ]
        for preset in EasingPreset.all {
            list.append(.item(preset.name, checked: shared == .bezier(preset.curve)) {
                controller.setEasing(.bezier(preset.curve))
            })
        }
        list.append(.separator)
        list.append(.item("Custom Curve", checked: shared.map(Self.isCustomCurve) ?? false) {
            if case .bezier(let c) = shared { controller.setEasing(.bezier(c)) } else { controller.setEasing(.bezier(.easeInOut)) }
        })
        list.append(.item("Spring", checked: { if case .spring = shared { return true } else { return false } }()) {
            if case .spring = shared { return }
            controller.setEasing(.spring(MotionModel.Spring()))
        })
        return list
    }

    static func name(_ easing: Easing) -> String {
        switch easing {
        case .linear: return "Linear"
        case .hold: return "Hold"
        case .bezier(let c): return EasingPreset.named(c)?.name ?? "Custom Curve"
        case .spring: return "Spring"
        }
    }

    static func isCustomCurve(_ easing: Easing) -> Bool {
        if case .bezier(let c) = easing { return EasingPreset.named(c) == nil }
        return false
    }
}

// MARK: - Curve

/// The segment's timing curve, time across and progress up, with its two
/// handles to drag. Room above and below the square leaves space for curves
/// that overshoot.
private struct CurveEditor: View {
    let curve: CubicBezier
    let controller: EditorController

    @State private var grabbed: Int?

    private let lowest = -0.3, highest = 1.3

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { context, _ in
                let box = CGRect(x: point(0, 1, size).x, y: point(0, 1, size).y,
                                 width: point(1, 0, size).x - point(0, 1, size).x,
                                 height: point(1, 0, size).y - point(0, 1, size).y)
                context.stroke(Path(box), with: .color(Theme.border), lineWidth: 1)
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
                    controller.updateEasing(.bezier(c))
                }
                .onEnded { _ in
                    grabbed = nil
                    controller.end()
                })
        }
    }

    private let pad: CGFloat = 10

    private func point(_ x: Double, _ y: Double, _ size: CGSize) -> CGPoint {
        CGPoint(x: pad + x * (size.width - pad * 2),
                y: pad + (highest - y) / (highest - lowest) * (size.height - pad * 2))
    }

    /// Handles keep to the square's width, since time cannot run backwards
    /// inside a segment, but can go well above and below it.
    private func value(at p: CGPoint, _ size: CGSize) -> (x: Double, y: Double) {
        let x = (p.x - pad) / (size.width - pad * 2)
        let y = highest - (p.y - pad) / (size.height - pad * 2) * (highest - lowest)
        return (min(max(x, 0), 1), min(max(y, -1), 2))
    }
}

// MARK: - Spring

/// A spring's three settings and the motion they make. Changing them moves
/// the keyframe that ends the segment to where the new spring settles.
private struct SpringEditor: View {
    let spring: MotionModel.Spring
    let controller: EditorController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledRow(label: "Stiffness") {
                UnitField(value: spring.stiffness, decimals: 1, accepts: { $0 > 0 }) { v in set { $0.stiffness = v } }
            }
            .help("How hard the spring pulls. Stiffer is faster.")
            LabeledRow(label: "Damping") {
                UnitField(value: spring.damping, decimals: 1, accepts: { $0 >= 0 }) { v in set { $0.damping = v } }
            }
            .help("How quickly the bounce dies away. Less damping bounces more.")
            LabeledRow(label: "Mass") {
                UnitField(value: spring.mass, decimals: 2, accepts: { $0 > 0 }) { v in set { $0.mass = v } }
            }
            .help("How heavy the thing on the spring is. Heavier is slower and swings further.")
            ReadoutRow(label: "Settles in", value: String(format: "%.2fs", spring.settleDuration))
            Canvas { context, size in
                let settle = spring.settleDuration
                var path = Path()
                let lowest = -0.2, highest = 1.6
                func y(_ v: Double) -> CGFloat { (highest - v) / (highest - lowest) * size.height }
                path.move(to: CGPoint(x: 0, y: y(0)))
                for i in 1...100 {
                    let t = Double(i) / 100
                    path.addLine(to: CGPoint(x: t * size.width, y: y(spring.position(at: t * settle))))
                }
                var target = Path()
                target.move(to: CGPoint(x: 0, y: y(1)))
                target.addLine(to: CGPoint(x: size.width, y: y(1)))
                context.stroke(target, with: .color(Theme.border), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                context.stroke(path, with: .color(Theme.accent), lineWidth: 2)
            }
            .frame(height: 70)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.canvas))
        }
    }

    private func set(_ change: (inout MotionModel.Spring) -> Void) {
        var s = spring
        change(&s)
        controller.setEasing(.spring(s))
    }
}
