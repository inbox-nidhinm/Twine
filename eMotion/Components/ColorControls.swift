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

/// A plain square of colour that opens the colour panel. SwiftUI's own
/// `ColorPicker` draws a capsule that reads as a button rather than as the
/// colour it shows.
///
/// For now this opens the system colour panel. Flip's own picker card
/// replaces it when fills arrive in milestone 3.
struct ColorWell: View {
    let color: RGBA
    var size: CGFloat = 48
    /// Every change while the panel is being dragged in. The first arrives
    /// after `onBegin`, and `onEnd` comes once the panel goes quiet.
    let onChange: (RGBA) -> Void
    var onBegin: () -> Void = {}
    var onEnd: () -> Void = {}

    @State private var hovering = false

    var body: some View {
        Button {
            ColorPanelBridge.shared.present(color, onBegin: onBegin, onChange: onChange, onEnd: onEnd)
        } label: {
            RoundedRectangle(cornerRadius: Theme.radiusWell)
                .fill(color.opaque)
                .frame(width: size, height: size)
                // The hairline answers the pointer, not the fill: a hover that
                // tinted the square would be showing the wrong colour.
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusWell)
                    .strokeBorder(hovering ? Theme.edgeHover : Theme.edge, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Six hex digits, typed. Commits on return or on losing focus, and puts the
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
                .onChange(of: color) { _, now in if !focused { text = now.hex6 } }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.control)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
    }

    private func apply() {
        if var parsed = RGBA(hex: text) {
            parsed.a = color.a
            if parsed != color { commit(parsed) }
        }
        text = color.hex6
    }
}

/// Routes the shared `NSColorPanel` to whichever well opened it last.
///
/// The panel reports every step of a drag as a separate change and never says
/// when a drag ends, so the bridge treats a quarter second of quiet as the end
/// of one continuous edit. That makes a drag across the colour wheel one undo
/// step rather than hundreds.
@MainActor
final class ColorPanelBridge: NSObject {
    static let shared = ColorPanelBridge()

    private var onBegin: () -> Void = {}
    private var onChange: (RGBA) -> Void = { _ in }
    private var onEnd: () -> Void = {}
    private var editing = false
    private var quiet: Timer?

    func present(_ color: RGBA, onBegin: @escaping () -> Void, onChange: @escaping (RGBA) -> Void,
                 onEnd: @escaping () -> Void) {
        finish()
        self.onBegin = onBegin
        self.onChange = onChange
        self.onEnd = onEnd

        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.showsAlpha = true
        panel.isContinuous = true
        panel.color = color.nsColor
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.orderFront(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        if !editing {
            editing = true
            onBegin()
        }
        onChange(RGBA(sender.color))
        quiet?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        // Both modes, so the timer still runs while the panel is being dragged in.
        RunLoop.main.add(timer, forMode: .common)
        quiet = timer
    }

    private func finish() {
        quiet?.invalidate()
        quiet = nil
        guard editing else { return }
        editing = false
        onEnd()
    }
}
