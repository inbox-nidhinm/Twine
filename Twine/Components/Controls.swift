import SwiftUI
import Theme

/// Label above, then a chunky track the full width of the panel with the value
/// drawn inside its right-hand end. The thumb is the right end of one white
/// pill that grows with the value, not a knob.
///
/// `range` is only what the track spans. Typing a value outside it is allowed
/// everywhere a slider has a field beside it; the pill simply pins at the end.
struct SliderRow<Accessory: View>: View {
    let label: String
    let value: Double
    let range: ClosedRange<Double>
    var readout: (Double) -> String = { "\(Int($0.rounded()))" }
    /// Called on every step of a drag. The first call of a drag comes after
    /// `onBegin`, so the owner can open one continuous undo step.
    var onChange: (Double) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}
    /// Sits at the end of the label's line, such as a stopwatch.
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(label)
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                accessory()
            }
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

extension SliderRow where Accessory == EmptyView {
    init(label: String, value: Double, range: ClosedRange<Double>, readout: @escaping (Double) -> String = { "\(Int($0.rounded()))" },
         onChange: @escaping (Double) -> Void, onBegin: @escaping () -> Void = {}, onEnd: @escaping () -> Void = {}) {
        self.init(label: label, value: value, range: range, readout: readout, onChange: onChange,
                  onBegin: onBegin, onEnd: onEnd, accessory: { EmptyView() })
    }
}

/// The switch, built from the slider's parts: the same track and the same
/// white pill, moved to one end or the other. Off sits in the canvas's dark,
/// on in the inspector's grey for chosen things.
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
                    .fill(isOn ? (hovering ? Theme.chosenHover : Theme.chosen) : Theme.canvas)
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

/// A check mark and its name, for a setting that is simply on or off in a
/// section that already names what it is about, such as Clip content. The
/// whole row is the button.
struct CheckRow: View {
    let label: String
    let isOn: Bool
    let toggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: Theme.radiusSwatchMark + 1)
                    .fill(isOn ? Theme.textPrimary : .clear)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusSwatchMark + 1)
                        .strokeBorder(isOn ? .clear : hovering ? Theme.edgeHover : Theme.textTertiary, lineWidth: 1))
                    .overlay {
                        if isOn {
                            IconView(.check, size: Theme.checkbox - 2, lineWidth: 2)
                                .foregroundStyle(Theme.canvas)
                        }
                    }
                    .frame(width: Theme.checkbox, height: Theme.checkbox)
                Text(label)
                    .font(ThemeFont.label)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: Theme.panelRow)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A row of mutually exclusive words, the chosen one raised in grey.
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
                    .fill(isOn ? Theme.chosen : hovering ? Theme.rowHover : .clear))
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
                // Follows the value unless the field holds typing of its own.
                .onChange(of: value) { old, now in if !focused || text == format(old) { text = format(now) } }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        // A click anywhere in the box, its letter included, starts typing.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func format(_ v: Double) -> String {
        let number = decimals == 0 ? String(Int(v.rounded())) : Self.trimmed(v, decimals)
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    /// Up to `decimals` places, with trailing zeros dropped, so 5 reads `5`
    /// and 2.5 reads `2.5` rather than `2.50`.
    static func trimmed(_ v: Double, _ decimals: Int) -> String {
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
            // The new value, not `value`: that still holds the old one until
            // the view updates, and showing it would put the old number back
            // the moment the field lost focus.
            text = format(v)
        } else {
            text = format(value)
        }
    }
}

/// A number that may be left empty. Empty shows `placeholder` greyed, the
/// value the field falls back to; typing a number sets it, and deleting the
/// number empties it again.
struct OptionalField: View {
    var unit: String = ""
    let value: Double?
    let placeholder: Double
    var decimals: Int = 0
    var suffix: String = ""
    var accepts: (Double) -> Bool = { _ in true }
    /// Nil when the field is emptied.
    let commit: (Double?) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            if !unit.isEmpty {
                Text(unit)
                    .font(ThemeFont.unit)
                    .foregroundStyle(Theme.textTertiary)
            }
            TextField("", text: $text, prompt: Text(format(placeholder)).foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, now in if !now { apply() } }
                .onAppear { text = value.map(format) ?? "" }
                .onChange(of: value) { old, now in
                    if !focused || text == (old.map(format) ?? "") { text = now.map(format) ?? "" }
                }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        // A click anywhere in the box, its letter included, starts typing.
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func format(_ v: Double) -> String {
        let number = decimals == 0 ? String(Int(v.rounded())) : UnitField.trimmed(v, decimals)
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    private func apply() {
        var typed = text.trimmingCharacters(in: .whitespaces)
        if !suffix.isEmpty, typed.hasSuffix(suffix) { typed.removeLast(suffix.count) }
        typed = typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if typed.isEmpty {
            if value != nil { commit(nil) }
            text = ""
        } else if let v = Double(typed), v.isFinite, accepts(v) {
            if value.map({ abs($0 - v) > .ulpOfOne }) ?? true { commit(v) }
            text = format(v)
        } else {
            text = value.map(format) ?? ""
        }
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
/// The whole row is the button when it folds, so a click anywhere on it works.
struct SectionHeader: View {
    let title: String
    var isOpen: Bool? = nil
    var toggle: () -> Void = {}

    var body: some View {
        if isOpen != nil {
            Button { withAnimation(.easeOut(duration: 0.14)) { toggle() } } label: { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }

    private var row: some View {
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
    }
}

/// A whole number with minus and plus either side, for counts where a slider
/// would be silly: a polygon's sides, a star's points.
struct StepRow: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    let commit: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.labelWidth, alignment: .leading)
                .lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                StepButton(icon: .minus, disabled: value <= range.lowerBound) { commit(max(range.lowerBound, value - 1)) }
                Text("\(value)")
                    .font(ThemeFont.label)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 28)
                StepButton(icon: .plus, disabled: value >= range.upperBound) { commit(min(range.upperBound, value + 1)) }
            }
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        }
        .frame(height: Theme.panelRow)
    }
}

private struct StepButton: View {
    let icon: Icon
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 15)
                .foregroundStyle(disabled ? Theme.textTertiary.opacity(0.4)
                                 : hovering ? Theme.textPrimary : Theme.textSecondary)
                .frame(width: 22, height: Theme.control)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(hovering && !disabled ? Theme.panelHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// A section's title with actions at its end, such as adding a fill. For
/// sections that do not fold.
struct HeaderRow<Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
            accessory()
        }
        .padding(.leading, Theme.panelPad)
        .padding(.trailing, Theme.panelPad - 4)
        .frame(height: Theme.button)
    }
}
