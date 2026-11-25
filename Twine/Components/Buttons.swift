import SwiftUI
import Theme

/// The glyph every bar button is drawn from, shared so the plain button and
/// the tool button cannot drift apart.
struct BarGlyph: View {
    let icon: Icon
    var isOn: Bool = false
    var hovering: Bool = false
    var disabled: Bool = false
    var size: CGFloat = Theme.glyph
    var iconBox: CGFloat = Theme.icon
    /// What a hover lifts to. On a raised ground, such as the tools tray, pass
    /// `panelHover`, the next rung up, or the hover would not show.
    var hoverFill: Color = Theme.panelRaised.opacity(0.6)
    /// What shows the button is on: `chosen`, DialKit's grey, for tools and
    /// switches alike; the accent is kept for the selection.
    var onFill: Color = Theme.chosen
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
    var size: CGFloat = Theme.glyph
    var iconBox: CGFloat = Theme.icon
    var hoverFill: Color = Theme.panelRaised.opacity(0.6)
    var onFill: Color = Theme.chosen
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
        .accessibilityLabel(help)
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
            // DialKit's button: the word centred, secondary until the
            // pointer comes, on a row's ground that lifts under it.
            HStack(spacing: Theme.space6) {
                if let icon { IconView(icon, size: Theme.iconRow) }
                Text(title).font(ThemeFont.label)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(disabled ? Theme.textTertiary.opacity(0.45) : hovering ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, Theme.space8)
            .frame(height: Theme.button)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering && !disabled ? Theme.panelHover : Theme.panelRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// A short button with a word on it at the head of a panel, level with the
/// mode switch beside it and as quiet: Export.
struct HeadButton: View {
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Theme.space12)
                .frame(height: Theme.panelRow)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl + 1)
                    .fill(hovering ? Theme.panelHover : Theme.panelRaised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

/// The one button that does a panel's main thing, filled with the accent:
/// Export. `quiet` gives it a plain button's colours in the same place, for
/// what is not the main thing (Cancel while exporting).
struct PrimaryButton: View {
    let title: String
    var disabled: Bool = false
    var quiet: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(quiet ? Theme.textPrimary : Theme.textOnColor.opacity(disabled ? 0.5 : 1))
                .frame(maxWidth: .infinity)
                .frame(height: Theme.primaryButton)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }

    /// The panel button's grounds when quiet, the accent's otherwise.
    private var fill: Color {
        if quiet { return hovering ? Theme.panelRaised : Theme.panelRaised.opacity(0.5) }
        return disabled ? Theme.accent.opacity(0.4) : hovering ? Theme.accentHover : Theme.accent
    }
}

/// A small square glyph button for panel headers and rows, which lights its
/// ground only under the pointer. Its icon reads as the other controls' do
/// while it can be used; only a button that cannot is dimmed.
struct IconButton: View {
    let icon: Icon
    var help: String
    var size: CGFloat = Theme.glyph
    var iconBox: CGFloat = Theme.iconRow
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            IconView(icon, size: iconBox)
                .foregroundStyle(!isEnabled ? Theme.textTertiary : hovering ? Theme.textPrimary : Theme.textSecondary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                    .fill(hovering && isEnabled ? Theme.panelHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
