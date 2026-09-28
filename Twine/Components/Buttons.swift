import SwiftUI
import Theme

/// The glyph every bar button is drawn from, shared so the plain button and
/// the tool button cannot drift apart.
struct BarGlyph: View {
    let icon: Icon
    var isOn: Bool = false
    var hovering: Bool = false
    var disabled: Bool = false
    var size: CGFloat = Theme.control
    var iconBox: CGFloat = Theme.icon
    /// What a hover lifts to. On a raised ground, such as the tools tray, pass
    /// `panelHover`, the next rung up, or the hover would not show.
    var hoverFill: Color = Theme.panelRaised.opacity(0.6)
    /// What shows the button is on: the accent for tools, `chosen` for a
    /// switch that is on, as in the inspector.
    var onFill: Color = Theme.accent
    /// The icon in full white without being on, as the pause button is
    /// while playing.
    var lit: Bool = false
    /// Hover whitens the icon (with a clear `hoverFill`) rather than
    /// lifting a fill behind it.
    var hoverLights: Bool = false

    private var fill: Color {
        if isOn { return onFill }
        return hovering && !disabled ? hoverFill : .clear
    }

    var body: some View {
        IconView(icon, size: iconBox)
            .frame(width: size, height: size)
            .foregroundStyle(isOn ? Theme.textOnColor
                             : disabled ? Theme.textTertiary.opacity(0.4)
                             : lit || (hoverLights && hovering) ? Theme.textPrimary
                             : Theme.textSecondary)
            .background(RoundedRectangle(cornerRadius: Theme.radius(forButton: size)).fill(fill))
            .contentShape(Rectangle())
    }
}

struct BarButton: View {
    let icon: Icon
    var help: String
    var isOn: Bool = false
    var disabled: Bool = false
    var size: CGFloat = Theme.control
    var iconBox: CGFloat = Theme.icon
    var hoverFill: Color = Theme.panelRaised.opacity(0.6)
    var onFill: Color = Theme.accent
    var lit: Bool = false
    var hoverLights: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            BarGlyph(icon: icon, isOn: isOn, hovering: hovering, disabled: disabled,
                     size: size, iconBox: iconBox, hoverFill: hoverFill, onFill: onFill, lit: lit, hoverLights: hoverLights)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// A wide button with a word on it, for panels, where an icon alone would be
/// a riddle.
struct PanelButton: View {
    let title: String
    var icon: Icon?
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { IconView(icon, size: 16) }
                Text(title).font(ThemeFont.label)
                Spacer(minLength: 0)
            }
            .foregroundStyle(disabled ? Theme.textTertiary.opacity(0.45) : Theme.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: Theme.button)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering && !disabled ? Theme.panelRaised : Theme.panelRaised.opacity(0.5)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// The one button that does a panel's main thing, filled with the accent:
/// Export.
struct PrimaryButton: View {
    let title: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textOnColor.opacity(disabled ? 0.5 : 1))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.primaryButton)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(disabled ? Theme.accent.opacity(0.4) : hovering ? Theme.accentHover : Theme.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// A small square glyph button for panel headers and rows, which lights its
/// ground only under the pointer.
struct IconButton: View {
    let icon: Icon
    var help: String
    var size: CGFloat = Theme.control
    var iconBox: CGFloat = 15
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            IconView(icon, size: iconBox)
                .foregroundStyle(hovering && isEnabled ? Theme.textPrimary : Theme.textTertiary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(hovering && isEnabled ? Theme.panelRaised : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
