import SwiftUI
import AppKit
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
                        RoundedRectangle(cornerRadius: Theme.radiusGrip)
                            .fill(hovering || grab != nil ? Theme.grip : .clear)
                            .frame(width: Theme.gripWidth, height: Theme.gripHeight)
                            .padding(.trailing, thumbWidth / 2 - Theme.gripWidth / 2)
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
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusGrip).fill(Theme.grip).frame(width: Theme.gripWidth, height: Theme.gripHeight))
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
                            IconView(.check, size: Theme.checkbox - 2, lineWidth: Theme.checkStroke)
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
    /// Drawn in place of each title, which becomes its tooltip.
    var icon: ((Value) -> Icon)? = nil
    let select: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Segment(title: title(option), icon: icon?(option), isOn: option == selection) { select(option) }
            }
        }
        .padding(Theme.trayPad)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 1).fill(Theme.panelRaised))
        .frame(height: Theme.panelRow + 4)
    }
}

private struct Segment: View {
    let title: String
    var icon: Icon? = nil
    let isOn: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    IconView(icon, size: 15)
                } else {
                    Text(title)
                        .font(ThemeFont.label)
                        .lineLimit(1)
                }
            }
                .foregroundStyle(isOn ? Theme.textOnColor : Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                    .fill(isOn ? Theme.chosen : hovering ? Theme.rowHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(icon == nil ? "" : title)
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
    /// Drawn in place of the name, such as the arc on a joined arc field.
    var icon: Icon? = nil
    /// Square inside a `JoinedFields`, which rounds the whole.
    var corner: CGFloat = Theme.radiusControl
    let value: Double
    var decimals: Int = 0
    var suffix: String = ""
    /// How much a point of dragging across the field changes it; nil is
    /// `ScrubSurface.step(for:)`.
    var step: Double? = nil
    var accepts: (Double) -> Bool = { _ in true }
    let commit: (Double) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.scrubbing) private var scrubbing

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                IconView(icon, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            } else if !unit.isEmpty {
                // Never cut short: the number gives way first.
                Text(unit)
                    .font(ThemeFont.unit)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .liftedFieldText()
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, now in if !now { apply() } }
                .onAppear { text = format(value) }
                // Follows the value unless the field holds typing of its own.
                .onChange(of: value) { old, now in if !focused || text == format(old) { text = format(now) } }
            // The unit stays put at the end, typed or not.
            if !suffix.isEmpty { UnitSuffix(suffix) }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: corner).fill(Theme.panelRaised))
        .focusRing(focused, corner: corner)
        // A click anywhere in the box, its letter included, starts typing;
        // a drag across it changes the number.
        .overlay {
            if !focused {
                ScrubSurface(start: { value }, step: step ?? ScrubSurface.step(for: suffix), accepts: accepts,
                             commit: commit, focus: { ScrubSurface.focus { focused = true } }, scrubbing: scrubbing)
            }
        }
    }

    /// The number alone: its unit is drawn beside it.
    private func format(_ v: Double) -> String {
        decimals == 0 ? String(Int(v.rounded())) : Self.trimmed(v, decimals)
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
    /// Drawn in place of the name, as in `UnitField`.
    var icon: Icon? = nil
    let value: Double?
    let placeholder: Double
    var decimals: Int = 0
    var suffix: String = ""
    var step: Double? = nil
    var accepts: (Double) -> Bool = { _ in true }
    /// Nil when the field is emptied.
    let commit: (Double?) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.scrubbing) private var scrubbing

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                IconView(icon, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            } else if !unit.isEmpty {
                // Never cut short: the number gives way first.
                Text(unit)
                    .font(ThemeFont.unit)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize()
            }
            TextField("", text: $text, prompt: Text(format(placeholder)).foregroundStyle(Theme.textTertiary))
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .liftedFieldText()
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, now in if !now { apply() } }
                .onAppear { text = value.map(format) ?? "" }
                .onChange(of: value) { old, now in
                    if !focused || text == (old.map(format) ?? "") { text = now.map(format) ?? "" }
                }
            if !suffix.isEmpty { UnitSuffix(suffix) }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        .focusRing(focused)
        // A click starts typing; a drag changes the number, from the one
        // it falls back to while empty.
        .overlay {
            if !focused {
                ScrubSurface(start: { value ?? placeholder }, step: step ?? ScrubSurface.step(for: suffix),
                             accepts: accepts, commit: { commit($0) },
                             focus: { ScrubSurface.focus { focused = true } }, scrubbing: scrubbing)
            }
        }
    }

    private func format(_ v: Double) -> String {
        decimals == 0 ? String(Int(v.rounded())) : UnitField.trimmed(v, decimals)
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

/// A name above and controls filling the whole width under it, as Easing
/// sits over its menu: for rows of two fields that need the room, such as
/// an action's From and To.
struct StackedRow<Accessory: View, Content: View>: View {
    let label: String
    /// When set, the name is a menu of these, such as To or By.
    var menu: [MenuEntry]? = nil
    /// Swaps an action's From and To: a button in the button column level
    /// with the name, between the two rows.
    var swap: (() -> Void)? = nil
    /// A button that acts on the fields, such as emptying them or linking
    /// them, in the button column level with them.
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(label: String, menu: [MenuEntry]? = nil, swap: (() -> Void)? = nil, @ViewBuilder accessory: @escaping () -> Accessory,
         @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.menu = menu
        self.swap = swap
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                if let menu {
                    MenuLabel(title: label, entries: menu)
                } else {
                    Text(label)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .rowButton { if let swap { SwapButton(action: swap) } }
            .frame(height: 14)
            if Accessory.self == EmptyView.self {
                fields
            } else {
                fields.rowButton { accessory() }
            }
        }
    }

    private var fields: some View {
        HStack(spacing: 8) { content() }
            .frame(height: Theme.panelRow)
    }
}

extension StackedRow where Accessory == EmptyView {
    init(label: String, menu: [MenuEntry]? = nil, swap: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(label: label, menu: menu, swap: swap, accessory: { EmptyView() }, content: content)
    }
}

/// Swaps an action's From and To, so it plays backwards.
struct SwapButton: View {
    let action: () -> Void

    var body: some View {
        IconButton(icon: .swap, help: "Swap From and To", action: action)
    }
}

/// A row's name that is also a menu: the name with a small chevron, lighter
/// under the pointer, opening its choices just below it.
struct MenuLabel: View {
    let title: String
    let entries: [MenuEntry]

    @Environment(MenuHost.self) private var menus
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var body: some View {
        Button {
            menus.show(entries, at: CGPoint(x: frame.minX, y: frame.maxY + 4))
        } label: {
            HStack(spacing: 2) {
                Text(title)
                    .font(ThemeFont.label)
                    .lineLimit(1)
                IconView(.chevronDown, size: 11)
            }
            .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
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
            .frame(height: Theme.hairline)
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
                .frame(width: Theme.rowIconButton, height: Theme.control)
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
        .padding(.trailing, Theme.buttonInset)
        .frame(height: Theme.button)
    }
}

// MARK: - The inspector's grid

/// Lifts a text field's text by `Theme.fieldTextLift` screen pixels, so what
/// is typed sits centred in its box as a label's words do.
private struct LiftedFieldText: ViewModifier {
    @Environment(\.displayScale) private var scale

    func body(content: Content) -> some View {
        content.offset(y: -Theme.fieldTextLift / max(scale, 1))
    }
}

extension View {
    func liftedFieldText() -> some View { modifier(LiftedFieldText()) }
}

extension View {
    /// A section's body on the inspector's grid: its rows start at the
    /// panel's inset and stop short of the button column, which lines up
    /// with the section headers' add and remove buttons.
    func gridBody() -> some View {
        padding(.leading, Theme.panelPad)
            .padding(.trailing, Theme.buttonInset + Theme.rowGutter)
    }

    /// A section's space under its rows. A section with nothing but its
    /// header (no stroke, no effects) splits it above and below instead, so
    /// the name sits centred between the dividers, at the same height.
    func sectionPadding(empty: Bool = false) -> some View {
        padding(.top, empty ? Theme.panelPad / 2 : 0)
            .padding(.bottom, empty ? Theme.panelPad / 2 : Theme.panelPad)
    }

    /// A row with a button that acts on it, placed in the button column
    /// level with the row. The row is laid out on a grid body, so the
    /// button reaches out into the column the body leaves free.
    func rowButton<Button: View>(alignment: VerticalAlignment = .center,
                                 @ViewBuilder _ button: () -> Button) -> some View {
        HStack(alignment: alignment, spacing: Theme.columnGap) {
            frame(maxWidth: .infinity)
            // Holds the column's width even when the button is not showing,
            // so the row still stops where the others do.
            ZStack {
                Color.clear.frame(width: Theme.control, height: 1)
                button()
            }
            .frame(width: Theme.control)
        }
        .padding(.trailing, -Theme.rowGutter)
    }
}

/// Several number fields joined into one box, split by thin rules, for
/// values that belong together, as Figma shows an ellipse's arc. Give the
/// fields `corner: 0`; the box rounds the whole.
struct JoinedFields<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        // The one-point gaps show the panel through, which draws the rules.
        HStack(spacing: 1) { content() }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
    }
}

/// A number field's unit, such as px or %, fixed at its end.
struct UnitSuffix: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(ThemeFont.label)
            .foregroundStyle(Theme.textTertiary)
            .lineLimit(1)
            .fixedSize()
    }
}

extension View {
    /// A thin line in the accent round a field while it has the keyboard,
    /// so it is plain which one is being typed in.
    func focusRing(_ isFocused: Bool, corner: CGFloat = Theme.radiusControl) -> some View {
        overlay(RoundedRectangle(cornerRadius: corner)
            .strokeBorder(isFocused ? Theme.accent : .clear, lineWidth: 1))
    }
}

// MARK: - Dragging numbers

/// What a number field's drag reports to, so the whole drag undoes as one
/// step. The inspector sets it; a field without it still drags, a step at
/// a time.
struct Scrubbing {
    let begin: (String) -> Void
    let end: () -> Void
}

extension EnvironmentValues {
    @Entry var scrubbing: Scrubbing? = nil
}

/// Laid over a number field while it is not being typed in: a drag across
/// it changes the number, as in Figma, and a click without a drag starts
/// typing with the number selected. Shift moves ten times as fast, Option a
/// tenth as fast. An AppKit view rather than a SwiftUI gesture, so every
/// press lands and the pointer stays the resize arrows throughout.
struct ScrubSurface: NSViewRepresentable {
    let start: () -> Double
    let step: Double
    let accepts: (Double) -> Bool
    let commit: (Double) -> Void
    let focus: () -> Void
    let scrubbing: Scrubbing?

    /// Seconds move by hundredths a point; everything else by whole units:
    /// pixels, degrees, percent.
    static func step(for suffix: String) -> Double { suffix == "s" ? 0.01 : 1 }

    /// Gives the field the keyboard, then selects its number, so typing
    /// replaces it, as a click in Figma does.
    @MainActor static func focus(_ take: @escaping () -> Void) {
        take()
        DispatchQueue.main.async { NSApp.sendAction(#selector(NSResponder.selectAll(_:)), to: nil, from: nil) }
    }

    func makeNSView(context: Context) -> ScrubView { ScrubView() }

    func updateNSView(_ view: ScrubView, context: Context) { view.surface = self }
}

/// Laid over a text field while it is not being typed in, so a click
/// gives it the keyboard with everything in it selected (through
/// `ScrubSurface.focus`), rather than a caret where the click landed.
struct ClickToType: NSViewRepresentable {
    let focus: () -> Void

    func makeNSView(context: Context) -> ClickToTypeView { ClickToTypeView() }

    func updateNSView(_ view: ClickToTypeView, context: Context) { view.focus = focus }
}

final class ClickToTypeView: NSView {
    var focus: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    // Set on every move too, as `ScrubView` does, since SwiftUI puts its
    // arrow back.
    override func cursorUpdate(with event: NSEvent) { NSCursor.iBeam.set() }
    override func mouseMoved(with event: NSEvent) { NSCursor.iBeam.set() }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) { focus?() }
}

final class ScrubView: NSView {
    var surface: ScrubSurface?

    private var pressX: CGFloat = 0
    private var lastX: CGFloat = 0
    /// The number as dragged, before rounding; nil until the pointer has
    /// moved far enough to count as a drag rather than a click.
    private var raw: Double?
    private var committed: Double = 0
    /// A press that moves less than this is a click.
    private let deadZone: CGFloat = 3

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.cursorUpdate, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    // SwiftUI puts its arrow back as the pointer moves, so the pointer is set
    // on every move, not only by a cursor rect.
    override func cursorUpdate(with event: NSEvent) { Cursors.resizeHorizontal.set() }
    override func mouseMoved(with event: NSEvent) { Cursors.resizeHorizontal.set() }

    override func mouseDown(with event: NSEvent) {
        pressX = event.locationInWindow.x
        lastX = pressX
        raw = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let surface else { return }
        let x = event.locationInWindow.x
        if raw == nil {
            guard abs(x - pressX) > deadZone else { return }
            let start = surface.start()
            raw = start
            committed = start
            lastX = x
            surface.scrubbing?.begin("Change Value")
        }
        Cursors.resizeHorizontal.set()
        let flags = event.modifierFlags
        let fine = flags.contains(.option)
        let speed = flags.contains(.shift) ? 10 : fine ? 0.1 : 1
        let quantum = surface.step * (fine ? 0.1 : 1)
        var value = ((raw ?? committed) + Double(x - lastX) * surface.step * speed)
        lastX = x
        value = (value / quantum).rounded() * quantum
        // Past a limit, it rests on the last value the field takes, so
        // dragging back moves it again at once.
        if !surface.accepts(value) {
            let back = committed > value ? quantum : -quantum
            var tries = 0
            while !surface.accepts(value) && tries < 10_000 {
                value += back
                tries += 1
            }
            if !surface.accepts(value) { value = committed }
        }
        raw = value
        guard abs(value - committed) > quantum / 2 else { return }
        committed = value
        surface.commit(value)
    }

    override func mouseUp(with event: NSEvent) {
        if raw == nil {
            surface?.focus()
        } else {
            surface?.scrubbing?.end()
        }
        raw = nil
    }
}
