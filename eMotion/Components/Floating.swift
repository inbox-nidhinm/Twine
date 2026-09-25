import SwiftUI
import AppKit
import Theme

extension View {
    /// The card every panel, bar and popup is drawn on. Each one floats over the
    /// canvas, so each needs its own edge: a border alone reads as a seam and a
    /// shadow alone as a smudge.
    func floatingPanel(corner: CGFloat = Theme.radiusPanel) -> some View {
        // The cursor area sits behind the fill, where it can never take a click.
        // It is there only to claim the arrow back from a canvas underneath.
        background(CursorArea())
            // Grained inside the background rather than over the finished card,
            // so the texture stays under the labels and glyphs.
            .background(RoundedRectangle(cornerRadius: corner)
                .fill(Theme.panel)
                .grained()
                .clipShape(RoundedRectangle(cornerRadius: corner)))
            .overlay(RoundedRectangle(cornerRadius: corner)
                .strokeBorder(Theme.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: corner))
            .shadow(color: Theme.shadow, radius: Theme.shadowRadius, y: Theme.shadowY)
    }
}

/// Gives the area it covers the arrow cursor.
///
/// A canvas that fills the window sets its tool's cursor over its whole
/// bounds, including the parts covered by floating panels. AppKit resolves
/// cursor rects per view and the topmost wins, so a panel that carries one of
/// these takes the arrow back without the canvas knowing where panels are.
struct CursorArea: NSViewRepresentable {
    var cursor: NSCursor = .arrow

    func makeNSView(context: Context) -> Area {
        let view = Area()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ view: Area, context: Context) {
        if view.cursor !== cursor {
            view.cursor = cursor
            view.window?.invalidateCursorRects(for: view)
        }
    }

    final class Area: NSView {
        var cursor: NSCursor = .arrow

        override func resetCursorRects() {
            discardCursorRects()
            addCursorRect(bounds, cursor: cursor)
        }

        /// Never takes a click from the controls it sits behind.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A titled card raised by a control, built from the panel's own parts rather
/// than `NSPopover`, which always draws an arrow and a light backing.
struct PopupCard<Accessory: View, Content: View>: View {
    let title: String
    var width: CGFloat = Theme.panelWidth
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(ThemeFont.labelStrong)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                accessory()
            }
            .padding(.horizontal, Theme.panelPad)
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 1) }

            VStack(alignment: .leading, spacing: 8) { content() }
                .padding(Theme.panelPad)
        }
        .frame(width: width)
        .floatingPanel()
    }
}

extension PopupCard where Accessory == EmptyView {
    init(title: String, width: CGFloat = Theme.panelWidth, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, width: width, accessory: { EmptyView() }, content: content)
    }
}

/// A window with no visible title bar: the content runs to the top edge and
/// the traffic lights float over it.
func makeChromelessWindow(size: NSSize, minSize: NSSize) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    // An empty unified toolbar makes the title bar tall enough that AppKit
    // centres the traffic lights about 20pt in from the corner: where any
    // control in the left panel sits. Flip moves the buttons there by hand,
    // but a document window re-lays its title bar out every time its title or
    // edited state changes, and moving the buttons against that fought AppKit
    // (and once, looped until the app crashed). This way AppKit places them.
    let toolbar = NSToolbar(identifier: "chrome")
    toolbar.allowsUserCustomization = false
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(Theme.canvas)
    window.minSize = minSize
    window.isRestorable = false
    window.center()
    return window
}
