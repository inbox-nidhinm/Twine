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

/// Places the window's traffic lights where any other control in the left
/// panel sits: the panel's inset plus its content padding, from the corner.
///
/// AppKit lays the buttons out again whenever the title bar changes: on
/// resize, on becoming key, and in a document window every time the title or
/// the edited state changes. So `keepPlaced` watches the buttons' frames and
/// puts them back. It does that a turn later rather than from inside AppKit's
/// own layout, once per burst of changes, and gives up after a few tries that
/// do not stick. Moving them synchronously from the notification recursed until
/// the app crashed, and an empty toolbar that let AppKit place them instead
/// broke hit testing in the inspector.
enum TrafficLights {
    static let origin = CGPoint(x: Theme.floatInset + Theme.panelPad, y: Theme.floatInset + Theme.panelPad)

    private static var pending: Set<ObjectIdentifier> = []
    private static var misses: [ObjectIdentifier: Int] = [:]

    static func keepPlaced(in window: NSWindow) {
        for button in buttons(of: window) {
            button.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: button,
                                                   queue: .main) { [weak window] _ in
                MainActor.assumeIsolated {
                    if let window { schedule(window) }
                }
            }
        }
        schedule(window)
    }

    private static func buttons(of window: NSWindow) -> [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
    }

    private static func schedule(_ window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard !pending.contains(key), misses[key, default: 0] < 3 else { return }
        pending.insert(key)
        DispatchQueue.main.async { [weak window] in
            pending.remove(key)
            guard let window else { return }
            if place(in: window) { misses[key] = 0 } else { misses[key, default: 0] += 1 }
        }
    }

    /// Resets the give-up count, for events after which placing should work
    /// again, such as the window coming on screen.
    static func retry(in window: NSWindow) {
        misses[ObjectIdentifier(window)] = 0
        schedule(window)
    }

    /// Returns true if the buttons are where they belong afterwards.
    @discardableResult
    private static func place(in window: NSWindow) -> Bool {
        let buttons = buttons(of: window)
        guard let close = buttons.first, let bar = close.superview, bar.frame.height > origin.y else { return false }
        // The title bar view is not flipped, so further down is a smaller y.
        let wantedMaxY = bar.frame.height - origin.y
        let dy = wantedMaxY - close.frame.maxY
        let dx = origin.x - close.frame.minX
        if abs(dx) <= 0.5 && abs(dy) <= 0.5 { return true }
        for button in buttons {
            button.setFrameOrigin(CGPoint(x: button.frame.minX + dx, y: button.frame.minY + dy))
        }
        return abs(close.frame.minX - origin.x) <= 0.5 && abs(close.frame.maxY - wantedMaxY) <= 0.5
    }
}

/// A window with no visible title bar: the content runs to the top edge and
/// the traffic lights float over it.
///
/// A click anywhere that is not the text field being edited ends the edit, the
/// way clicking away from a field does in Figma. AppKit's default keeps a
/// field focused through clicks on anything that cannot itself take focus,
/// which in a window of buttons and a canvas is almost everything.
final class ChromelessWindow: NSWindow {
    /// What gets the keyboard when nothing else wants it: the canvas, in a
    /// project window, so tool letters and the delete key work after a click
    /// on a panel button.
    weak var preferredResponder: NSResponder?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let fieldEditor = firstResponder as? NSText,
           let field = fieldEditor.delegate as? NSView,
           let content = contentView {
            let hit = content.hitTest(content.convert(event.locationInWindow, from: nil))
            if hit.map({ !$0.isDescendant(of: field) }) ?? true {
                // Resigning commits the field, the same as pressing Return.
                makeFirstResponder(preferredResponder)
            }
        }
        super.sendEvent(event)
    }

    /// Nothing is focused when a window opens. Left alone, AppKit hands the
    /// keyboard to the first text field it finds, and typing then goes into
    /// the composition's width.
    func clearInitialFocus() {
        DispatchQueue.main.async { [weak self] in self?.makeFirstResponder(self?.preferredResponder) }
    }
}

func makeChromelessWindow(size: NSSize, minSize: NSSize) -> ChromelessWindow {
    let window = ChromelessWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = NSColor(Theme.canvas)
    window.minSize = minSize
    window.isRestorable = false
    window.center()
    TrafficLights.keepPlaced(in: window)
    return window
}
