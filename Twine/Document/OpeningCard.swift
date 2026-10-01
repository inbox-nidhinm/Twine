import AppKit
import SwiftUI
import Theme

/// A card in the middle of the window while a project opens: the loader
/// ring and the project's name. Opening a large one holds the main thread
/// while the editor is built, so nothing here may need it once shown: the
/// card is drawn once, and its ring turns and its fade in plays in Core
/// Animation, which keeps going while the app is busy. It comes in only
/// after `delay`, so a project that opens at once shows nothing.
@MainActor
enum OpeningCard {
    private static var panel: NSWindow?
    /// When the card starts to show; before this it is clear.
    private static var appearsAt: CFTimeInterval = 0
    static let delay: CFTimeInterval = 0.3
    private static let fade: CFTimeInterval = 0.15

    /// Shows the card over `window`, ready to fade in, and commits it, so it
    /// reaches the screen before the work that follows begins.
    static func show(named name: String, over window: NSWindow) {
        hide(fading: false)
        guard window.isVisible, !window.isMiniaturized else { return }
        let margin = Theme.shadowRadius * 2
        let host = NSHostingView(rootView: Card(name: name).padding(margin))
        host.frame.size = host.fittingSize
        host.wantsLayer = true

        let size = host.frame.size
        let frame = window.frame
        let panel = NSWindow(contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                                 width: size.width, height: size.height),
                             styleMask: .borderless, backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.contentView = host
        window.addChildWindow(panel, ordered: .above)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()

        appearsAt = CACurrentMediaTime() + delay
        host.layer?.opacity = 1
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.beginTime = appearsAt
        fadeIn.duration = fade
        fadeIn.fillMode = .backwards
        host.layer?.add(fadeIn, forKey: "appear")
        self.panel = panel
        CATransaction.flush()
    }

    /// Takes the card away, fading if it had begun to show.
    static func hide(fading: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        let remove = { panel.parent?.removeChildWindow(panel); panel.orderOut(nil) }
        guard fading, CACurrentMediaTime() > appearsAt, let layer = panel.contentView?.layer else { return remove() }
        CATransaction.begin()
        CATransaction.setCompletionBlock(remove)
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = layer.presentation()?.opacity ?? 1
        fadeOut.toValue = 0
        fadeOut.duration = fade
        layer.opacity = 0
        layer.add(fadeOut, forKey: "appear")
        CATransaction.commit()
    }

    private struct Card: View {
        let name: String

        var body: some View {
            HStack(spacing: 8) {
                Ring().frame(width: Theme.loader, height: Theme.loader)
                Text("Opening \(name)")
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .fixedSize()
            .padding(.horizontal, Theme.panelPad)
            .padding(.vertical, Theme.panelPad)
            .floatingPanel()
            .preferredColorScheme(.dark)
        }
    }

    /// The notice card's loader, turning without the main thread.
    private struct Ring: NSViewRepresentable {
        func makeNSView(context: Context) -> RingView { RingView() }
        func updateNSView(_ view: RingView, context: Context) {}
    }

    final class RingView: NSView {
        private let track = CAShapeLayer()
        private let arc = CAShapeLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for shape in [track, arc] {
                shape.fillColor = nil
                shape.lineWidth = Theme.loaderLine
                layer?.addSublayer(shape)
            }
            track.strokeColor = NSColor(Theme.panelRaised).cgColor
            arc.strokeColor = NSColor(Theme.accent).cgColor
            arc.lineCap = .round
            arc.strokeEnd = 0.28
            let turn = CABasicAnimation(keyPath: "transform.rotation.z")
            turn.fromValue = 0
            // Clockwise on screen, as the notice card's turns.
            turn.toValue = -2 * Double.pi
            turn.duration = 0.9
            turn.repeatCount = .infinity
            turn.isRemovedOnCompletion = false
            arc.add(turn, forKey: "turn")
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not built from a nib") }

        override func layout() {
            super.layout()
            let circle = CGPath(ellipseIn: bounds.insetBy(dx: Theme.loaderLine / 2, dy: Theme.loaderLine / 2), transform: nil)
            for shape in [track, arc] {
                shape.frame = bounds
                shape.path = circle
            }
        }
    }
}
