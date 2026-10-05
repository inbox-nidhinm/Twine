import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
import Theme

/// The easings as tiles on a card beside the inspector, as in Jitter. A
/// click on a tile picks it and the card stays open; a click on the picked
/// one (its settings icon shows under the pointer) turns the card to its
/// graph and Intensity. Custom goes straight to its graph, with handles to
/// drag and the four numbers of its curve. It acts on the selected actions,
/// read afresh, so it follows every edit.
struct EasingCard: View {
    let controller: EditorController
    @State var showsGraph = false

    /// The easings in the order the tiles show them, Custom first.
    static let order: [EasingPreset] = [.smooth, .natural, .slowDown, .accelerate, .spring, .bounce,
                                        .overshoot, .impulse, .swing, .easeOutBack, .easeInBack, .none]

    private var shared: Easing? {
        let actions = controller.selectedActions
        guard let first = actions.first?.easing else { return nil }
        return actions.allSatisfy { $0.easing == first } ? first : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsGraph, let shared {
                graph(shared)
            } else {
                grid
            }
        }
        .frame(width: Theme.cardWidth)
        .floatingPanel()
    }

    // MARK: Tiles

    private var grid: some View {
        VStack(spacing: 0) {
            header { Text("Easing") }
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                    EasingTile(title: "Custom", easing: nil, chosen: isCustom, hasSettings: true) { pickCustom() }
                        .help("Your own curve, with handles to drag")
                    ForEach(Self.order, id: \.self) { preset in
                        EasingTile(title: preset.title, easing: easing(for: preset), chosen: isChosen(preset),
                                   hasSettings: preset != .none) { pick(preset) }
                    }
                }
                .padding(Theme.panelPad)
            }
            .frame(height: Theme.easingGridHeight)
        }
    }

    private var isCustom: Bool {
        if case .custom = shared { return true }
        return false
    }

    private func isChosen(_ preset: EasingPreset) -> Bool {
        if case .preset(preset, _) = shared { return true }
        return false
    }

    /// The tile's curve: the picked one as it is set, the rest at their own
    /// strength.
    private func easing(for preset: EasingPreset) -> Easing {
        if case .preset(preset, let intensity) = shared { return .preset(preset, intensity: intensity) }
        return .preset(preset, intensity: Easing.standardIntensity)
    }

    private func pick(_ preset: EasingPreset) {
        if isChosen(preset) {
            if preset != .none { showsGraph = true }
            return
        }
        controller.editActions("Easing") { $0.easing = .preset(preset, intensity: Easing.standardIntensity) }
    }

    private func pickCustom() {
        if !isCustom {
            controller.editActions("Easing") { action in
                // Starts from the curve the preset was making, so nothing
                // jumps, where the preset is a bezier.
                if case .preset(let p, let i) = action.easing {
                    action.easing = .custom(p.isCurve && p != .none ? p.curve(intensity: i) : .easeInOut)
                }
            }
        }
        showsGraph = true
    }

    // MARK: Graph

    @ViewBuilder private func graph(_ easing: Easing) -> some View {
        VStack(spacing: 0) {
            header(back: { showsGraph = false }) { Text(easing.title) }
            VStack(alignment: .leading, spacing: 12) {
                switch easing {
                case .custom(let curve):
                    CurveEditor(curve: curve, controller: controller)
                        .aspectRatio(1, contentMode: .fit)
                    BezierFields(curve: curve, controller: controller)
                case .preset(let preset, let intensity):
                    EasingGraph(easing: easing)
                        .aspectRatio(1, contentMode: .fit)
                    if preset != .none {
                        SliderRow(label: "Intensity", value: intensity * 100, range: 0...100,
                                  onChange: { v in controller.updateActions { $0.easing = .preset(preset, intensity: v / 100) } },
                                  onBegin: { controller.begin("Easing Intensity") },
                                  onEnd: { controller.end() })
                            .help("How strongly it eases. 50 is the easing as designed; 0 is a straight line.")
                    }
                }
            }
            .padding(Theme.panelPad)
        }
    }

    /// The card's title row, with a back arrow on the graph.
    private func header<Title: View>(back: (() -> Void)? = nil, @ViewBuilder title: () -> Title) -> some View {
        ZStack {
            title()
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: back == nil ? .leading : .center)
            if let back {
                IconButton(icon: .chevronLeft, help: "Back to the easings", action: back)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, back == nil ? Theme.panelPad : Theme.panelPad - 6)
        .frame(height: Theme.cardHeader)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.hairline) }
    }
}

/// One easing's square, its curve drawn in it and its name under it. Under
/// the pointer, one not picked plays a small box moving with the easing in
/// place of its curve (the user's choice); the picked one takes the chosen
/// fill and instead shows a settings icon at its foot, since a second click
/// opens its settings.
private struct EasingTile: View {
    let title: String
    /// Nil for Custom, which shows a plus.
    let easing: Easing?
    let chosen: Bool
    let hasSettings: Bool
    let action: () -> Void

    @State private var hovering = false
    /// When the pointer came in, so the preview starts from its beginning.
    @State private var hoverStart = Date()

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        GeometryReader { geo in
                            let side = min(geo.size.width, geo.size.height)
                            Group {
                                if let easing, hovering, !chosen {
                                    EasingPreview(easing: easing, since: hoverStart, side: side)
                                } else if let easing {
                                    // Half the square for 0 to 1, room above and
                                    // below for curves that pass the ends.
                                    EasingPath(easing: easing, low: -0.5, high: 1.5)
                                        .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                        .frame(width: side * 0.4, height: side * 0.8)
                                } else {
                                    IconView(.plus, size: Theme.icon + 4)
                                        .foregroundStyle(Theme.textPrimary)
                                }
                            }
                            .frame(width: geo.size.width, height: geo.size.height)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if chosen && hovering && hasSettings {
                            IconView(.settings, size: 15)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.bottom, 8)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.radiusWell)
                        .fill(chosen ? (hovering ? Theme.chosenHover : Theme.chosen) : hovering ? Theme.panelHover : Theme.panelRaised))
                Text(title)
                    .font(ThemeFont.label)
                    .foregroundStyle(chosen ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside && !hovering { hoverStart = Date() }
            hovering = inside
        }
    }
}

/// A small box sliding across a tile with the easing, from the left to the
/// right in a second, resting there a moment, then again.
private struct EasingPreview: View {
    let easing: Easing
    let since: Date
    let side: CGFloat

    private static let travel = 1.0, rest = 0.6

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(since)
            let phase = elapsed.truncatingRemainder(dividingBy: Self.travel + Self.rest)
            let p = easing.progress(min(phase / Self.travel, 1))
            let box = side * 0.16
            // Across the middle three fifths, so an overshoot has room.
            let from = side * 0.2, span = side * 0.6
            RoundedRectangle(cornerRadius: box * 0.25)
                .fill(Theme.thumb)
                .frame(width: box, height: box)
                .position(x: from + span * p, y: side / 2)
        }
        .frame(width: side, height: side)
    }
}

/// An easing's progress over time as a line: across is time, up is how far
/// along, from `low` at the bottom to `high` at the top.
nonisolated struct EasingPath: Shape {
    let easing: Easing
    var low = -0.3
    var high = 1.3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 120
        for k in 0...steps {
            let u = Double(k) / Double(steps)
            let point = CGPoint(x: rect.minX + u * rect.width,
                                y: rect.minY + (high - easing.progress(u)) / (high - low) * rect.height)
            if k == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// A preset's curve, large, on the same square the custom curve is edited
/// on, without handles.
private struct EasingGraph: View {
    let easing: Easing

    var body: some View {
        GeometryReader { geo in
            let box = CurveBox(size: geo.size)
            ZStack {
                box.frame
                EasingPath(easing: easing, low: CurveBox.lowest, high: CurveBox.highest)
                    .stroke(Theme.textPrimary, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(CurveBox.pad)
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.canvas))
    }
}

/// The square both graphs are drawn on: 0 to 1 across, and a little past 0
/// and 1 up, inside a small margin.
private struct CurveBox {
    static let lowest = -0.3, highest = 1.3
    static let pad: CGFloat = 10
    let size: CGSize

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: Self.pad + x * (size.width - Self.pad * 2),
                y: Self.pad + (Self.highest - y) / (Self.highest - Self.lowest) * (size.height - Self.pad * 2))
    }

    /// Handles keep to the square's width, since time cannot run backwards
    /// inside an action, but can go well above and below it.
    func value(at p: CGPoint) -> (x: Double, y: Double) {
        let x = (p.x - Self.pad) / (size.width - Self.pad * 2)
        let y = Self.highest - (p.y - Self.pad) / (size.height - Self.pad * 2) * (Self.highest - Self.lowest)
        return (min(max(x, 0), 1), min(max(y, -1), 2))
    }

    /// The square from 0 to 1 and its diagonal.
    var frame: some View {
        Canvas { context, _ in
            let a = point(0, 1), b = point(1, 0)
            context.stroke(Path(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)),
                           with: .color(Theme.border), lineWidth: 1)
            var diagonal = Path()
            diagonal.move(to: point(0, 0))
            diagonal.addLine(to: point(1, 1))
            context.stroke(diagonal, with: .color(Theme.border), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }
}

/// A custom curve with both handles to drag.
private struct CurveEditor: View {
    let curve: CubicBezier
    let controller: EditorController

    @State private var grabbed: Int?

    var body: some View {
        GeometryReader { geo in
            let box = CurveBox(size: geo.size)
            ZStack {
                box.frame
                Canvas { context, _ in
                    var shape = Path()
                    shape.move(to: box.point(0, 0))
                    for i in 1...80 {
                        let x = Double(i) / 80
                        shape.addLine(to: box.point(x, curve.value(at: x)))
                    }
                    context.stroke(shape, with: .color(Theme.textPrimary), lineWidth: 2)

                    let p1 = box.point(curve.x1, curve.y1), p2 = box.point(curve.x2, curve.y2)
                    var arms = Path()
                    arms.move(to: box.point(0, 0)); arms.addLine(to: p1)
                    arms.move(to: box.point(1, 1)); arms.addLine(to: p2)
                    context.stroke(arms, with: .color(Theme.textTertiary), lineWidth: 1)
                    for p in [p1, p2] {
                        let dot = Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10))
                        context.fill(dot, with: .color(Theme.thumb))
                        context.stroke(dot, with: .color(Theme.canvas), lineWidth: 1.5)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.canvas))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if grabbed == nil {
                        let p1 = box.point(curve.x1, curve.y1), p2 = box.point(curve.x2, curve.y2)
                        grabbed = hypot(g.startLocation.x - p1.x, g.startLocation.y - p1.y)
                            <= hypot(g.startLocation.x - p2.x, g.startLocation.y - p2.y) ? 1 : 2
                        controller.begin("Easing Curve")
                    }
                    let v = box.value(at: g.location)
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
}

/// A custom curve's four numbers, as CSS writes them: the first handle's
/// time and progress, then the second's.
private struct BezierFields: View {
    let curve: CubicBezier
    let controller: EditorController

    var body: some View {
        HStack(spacing: 6) {
            field(curve.x1, time: true, help: "When the first handle pulls, from 0 to 1") { $0.x1 = $1 }
            field(curve.y1, time: false, help: "How far along the first handle pulls") { $0.y1 = $1 }
            field(curve.x2, time: true, help: "When the second handle pulls, from 0 to 1") { $0.x2 = $1 }
            field(curve.y2, time: false, help: "How far along the second handle pulls") { $0.y2 = $1 }
        }
    }

    private func field(_ value: Double, time: Bool, help: String,
                       _ set: @escaping (inout CubicBezier, Double) -> Void) -> some View {
        UnitField(value: value, decimals: 2, step: 0.01,
                  accepts: { time ? ($0 >= 0 && $0 <= 1) : ($0 >= -1 && $0 <= 2) }) { v in
            var c = curve
            set(&c, v)
            controller.editActions("Easing Curve") { $0.easing = .custom(c) }
        }
        .help(help)
    }
}
