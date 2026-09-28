import SwiftUI
import AppKit
import MotionModel
import Theme

extension RGBA {
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var opaque: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        self.init(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

/// A plain square of colour that opens the app's colour picker beside it.
/// SwiftUI's own `ColorPicker` draws a capsule that reads as a button rather
/// than as the colour it shows.
struct ColorWell: View {
    let color: RGBA
    var size: CGFloat = 48
    /// What the picker's card is called.
    var title: String = "Colour"
    /// Every step of a drag in the picker. The first arrives after `onBegin`,
    /// and `onEnd` comes when the drag lets go, so a drag is one undo step.
    let onChange: (RGBA) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    @Environment(MenuHost.self) private var menus
    @State private var hovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            // Beside the well, towards the canvas, level with it.
            let x = frame.minX - Theme.cardWidth - Theme.floatGap * 2
            menus.showPopup(at: CGPoint(x: x, y: frame.minY - 40)) {
                PopupCard(title: title, width: Theme.cardWidth) {
                    ColorPicker(color: color, onChange: onChange, onBegin: onBegin, onEnd: onEnd)
                }
            }
        } label: {
            RoundedRectangle(cornerRadius: size >= 40 ? Theme.radiusWell : Theme.radiusControl)
                .fill(color.opaque)
                .frame(width: size, height: size)
                // The hairline answers the pointer, not the fill: a hover that
                // tinted the square would be showing the wrong colour.
                .overlay(RoundedRectangle(cornerRadius: size >= 40 ? Theme.radiusWell : Theme.radiusControl)
                    .strokeBorder(hovering ? Theme.edgeHover : Theme.edge, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}

/// Six hex digits, typed. A click selects them, so typing or pasting
/// replaces them. Commits on return or on losing focus, filling out a short
/// entry (`RGBA(typed:)`: `0` is `000000`, `1a` is `1A1A1A`), and puts the
/// old value back if what was typed is not a colour.
struct HexField: View {
    let color: RGBA
    let commit: (RGBA) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text("#")
                .font(ThemeFont.unit)
                .foregroundStyle(Theme.textTertiary)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(apply)
                .onChange(of: focused) { _, now in if !now { apply() } }
                .onAppear { text = color.hex6 }
                .onChange(of: color) { old, now in if !focused || text == old.hex6 { text = now.hex6 } }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
        .focusRing(focused)
        .overlay {
            if !focused { ClickToType { ScrubSurface.focus { focused = true } } }
        }
    }

    private func apply() {
        // The parsed colour, not `color`: that is still the old one until the
        // view updates, and it would come back when the field lost focus.
        if var parsed = RGBA(typed: text) {
            parsed.a = color.a
            if parsed != color { commit(parsed) }
            text = parsed.hex6
        } else {
            text = color.hex6
        }
    }
}
