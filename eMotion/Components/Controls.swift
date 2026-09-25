import SwiftUI
import Theme

/// Label above, then a chunky track the full width of the panel with the value
/// drawn inside its right-hand end. The thumb is the right end of one white
/// pill that grows with the value, not a knob.
///
/// `range` is only what the track spans. Typing a value outside it is allowed
/// everywhere a slider has a field beside it; the pill simply pins at the end.
struct SliderRow: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var readout: (Double) -> String = { "\(Int($0.rounded()))" }
    /// Called on every step of a drag. The first call of a drag comes after
    /// `onBegin`, so the owner can open one continuous undo step.
    var onChange: (Double) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            PillTrack(value: value, range: range, readout: readout(value),
                      onChange: onChange, onBegin: onBegin, onEnd: onEnd)
        }
        .padding(.vertical, 2)
    }
}

private struct PillTrack: View {
    let value: Double
    let range: ClosedRange<Double>
    let readout: String
    var onChange: (Double) -> Void
    var onBegin: () -> Void
    var onEnd: () -> Void

    /// Where in the thumb the drag started, so grabbing it by an edge does not
    /// snap its centre to the pointer. A press on the bare track seeds it with
    /// half the thumb, which makes a click on the track a jump-to.
    @State private var grab: CGFloat?
    @State private var hovering = false

    private let thumbWidth: CGFloat = 16
    private let readoutWidth: CGFloat = 46
    private let inset: CGFloat = 2

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - thumbWidth - inset * 2, 1)
            let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
            let t = min(max((value - range.lowerBound) / span, 0), 1)
            let fillRight = inset + thumbWidth + travel * CGFloat(t)
            // Once the fill reaches the number, the number goes dark instead of
            // disappearing white on white.
            let onFill = fillRight > geo.size.width - readoutWidth - 4

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.radiusTrack)
                    .fill(Theme.canvas)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusTrack)
                        .strokeBorder(Theme.edge, lineWidth: 1))

                // Covered area and handle in one shape, so there is no seam
                // between two whites.
                RoundedRectangle(cornerRadius: Theme.radiusTrack - 1)
                    .fill(Theme.thumb)
                    .frame(width: thumbWidth + travel * CGFloat(t), height: Theme.track - inset * 2)
                    .overlay(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(hovering || grab != nil ? Theme.grip : .clear)
                            .frame(width: 2, height: 10)
                            .padding(.trailing, thumbWidth / 2 - 1)
                    }
                    .padding(.leading, inset)

                Text(readout)
                    .font(ThemeFont.label)
                    .monospacedDigit()
                    .foregroundStyle(onFill ? Theme.textOnFill : Theme.textTertiary)
                    .lineLimit(1)
                    .frame(width: readoutWidth, alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let thumbX = inset + travel * CGFloat(t)
                        if grab == nil {
                            let onThumb = g.startLocation.x >= thumbX && g.startLocation.x <= thumbX + thumbWidth
                            grab = onThumb ? g.startLocation.x - thumbX : thumbWidth / 2
                            onBegin()
                        }
                        let x = min(max(g.location.x - (grab ?? 0) - inset, 0), travel)
                        onChange(range.lowerBound + Double(x / travel) * span)
                    }
                    .onEnded { _ in
                        grab = nil
                        onEnd()
                    }
            )
        }
        .frame(height: Theme.track)
    }
}

/// The switch, built from the slider's parts: the same track and the same
/// white pill, moved to one end or the other. Off sits in the canvas's dark,
/// on sits in the accent.
struct PillToggle: View {
    let isOn: Bool
    let toggle: () -> Void

    @State private var hovering = false

    private let width: CGFloat = 46
    private let inset: CGFloat = 2

    var body: some View {
        let thumb = Theme.track - inset * 2
        Button(action: toggle) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                RoundedRectangle(cornerRadius: Theme.radiusTrack)
                    .fill(isOn ? (hovering ? Theme.accentHover : Theme.accent) : Theme.canvas)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusTrack)
                        .strokeBorder(hovering ? Theme.edgeHover : Theme.edge, lineWidth: 1))
                RoundedRectangle(cornerRadius: Theme.radiusTrack - 1)
                    .fill(Theme.thumb)
                    .frame(width: thumb, height: thumb)
                    .overlay(RoundedRectangle(cornerRadius: 1).fill(Theme.grip).frame(width: 2, height: 10))
                    .padding(.horizontal, inset)
            }
            .frame(width: width, height: Theme.track)
            .animation(.easeOut(duration: 0.16), value: isOn)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct ToggleRow: View {
    let label: String
    let isOn: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            PillToggle(isOn: isOn, toggle: toggle)
        }
        .frame(height: Theme.panelRow + 4)
    }
}

/// A row of mutually exclusive words, one of them lit with the accent.
/// Unlabelled: it sits under a header that already names it.
struct SegmentRow<Value: Hashable>: View {
    let selection: Value
    let options: [Value]
    let title: (Value) -> String
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Segment(title: title(option), isOn: option == selection) { select(option) }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 1).fill(Theme.panelRaised))
        .frame(height: Theme.panelRow + 4)
    }
}

private struct Segment: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ThemeFont.label)
                .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                    .fill(isOn ? Theme.accent : hovering ? Theme.rowHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A number with its name inside the box, such as `W 1920`.
///
/// Values arrive as a plain number and leave through `commit`, so every edit
/// reaches the document as a command. The field never clamps to a slider's
/// range: anything `accepts` allows is taken. A suffix such as `s` or `%` is
/// shown after the number and may be typed or left off.
struct UnitField: View {
    var unit: String = ""
    let value: Double
    var decimals: Int = 0
    var suffix: String = ""
    var accepts: (Double) -> Bool = { _ in true }
    let commit: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            if !unit.isEmpty {
                Text(unit)
                    .font(ThemeFont.unit)
                    .foregroundStyle(Theme.textTertiary)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, now in if !now { apply() } }
                .onAppear { text = format(value) }
                .onChange(of: value) { _, now in if !focused { text = format(now) } }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
    }

    private func format(_ v: Double) -> String {
        let number = decimals == 0 ? String(Int(v.rounded())) : Self.trimmed(v, decimals)
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    /// Up to `decimals` places, with trailing zeros dropped, so 5 reads `5`
    /// and 2.5 reads `2.5` rather than `2.50`.
    private static func trimmed(_ v: Double, _ decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s
    }

    private func apply() {
        var typed = text.trimmingCharacters(in: .whitespaces)
        if !suffix.isEmpty, typed.hasSuffix(suffix) { typed.removeLast(suffix.count) }
        typed = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let v = Double(typed), v.isFinite, accepts(v), abs(v - value) > .ulpOfOne {
            commit(v)
        }
        text = format(value)
    }
}

/// A name on the left and a control filling the rest, for rows where the
/// control cannot carry its own name.
struct LabeledRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: Theme.labelWidth, alignment: .leading)
            content()
        }
        .frame(height: Theme.panelRow)
    }
}

struct ReadoutRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text(value)
                .font(ThemeFont.caption)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(height: 20)
    }
}

/// Between one section and the next, running the panel's full width.
struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

/// A section's name, and when it folds, a chevron that says which way it is.
struct SectionHeader: View {
    let title: String
    var isOpen: Bool? = nil
    var toggle: () -> Void = {}

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            if let isOpen {
                IconView(.chevronDown, size: 14)
                    .foregroundStyle(Theme.textTertiary)
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
            }
        }
        .padding(.horizontal, Theme.panelPad)
        .frame(height: Theme.button)
        .contentShape(Rectangle())
        .onTapGesture { if isOpen != nil { withAnimation(.easeOut(duration: 0.14)) { toggle() } } }
    }
}
