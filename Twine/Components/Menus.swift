import SwiftUI
import AppKit
import Observation
import Theme

/// One line of the app's own menu.
struct MenuEntry: Identifiable {
    enum Kind {
        /// `icon` is drawn where a tick would go, for menus of things with
        /// icons of their own, such as the kinds of action.
        case item(title: String, icon: Icon?, checked: Bool, disabled: Bool, action: () -> Void)
        case separator
        /// A small label naming the group of items under it.
        case header(String)
    }

    let id = UUID()
    let kind: Kind

    static func item(_ title: String, icon: Icon? = nil, checked: Bool = false, disabled: Bool = false,
                     _ action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(kind: .item(title: title, icon: icon, checked: checked, disabled: disabled, action: action))
    }

    static let separator = MenuEntry(kind: .separator)

    static func header(_ title: String) -> MenuEntry { MenuEntry(kind: .header(title)) }
}

/// The menu that is up in a window, if any.
///
/// The app draws its own menus, from the same card as the panels, rather than
/// using `NSMenu`: a system menu brings its own corner, highlight and
/// material, in a window that draws all three itself. One host per window,
/// so opening a menu anywhere closes the one already up. A menu opened from
/// inside a card (the stroke settings' Trim menu) goes over the card and
/// leaves it up: closing the menu goes back to the card.
@MainActor
@Observable
final class MenuHost {
    private(set) var entries: [MenuEntry] = []
    /// Where the menu's top-left goes, in the window's own coordinates with
    /// the origin at the top-left.
    private(set) var origin: CGPoint = .zero
    /// When true, `origin.y` is where the menu's bottom edge goes, for menus
    /// raised from a bar along the bottom of the window.
    private(set) var growsUp = false
    /// A card raised by a control, such as the colour picker, drawn on the
    /// same layer as menus and put away the same way, and where it goes.
    private(set) var popup: AnyView?
    private(set) var popupOrigin: CGPoint = .zero
    var isOpen: Bool { !entries.isEmpty || popup != nil }

    /// A menu, over the card that is up if any: nothing outside the card
    /// can be clicked while it is up, so a menu then comes from the card.
    func show(_ entries: [MenuEntry], at origin: CGPoint, growsUp: Bool = false) {
        self.entries = entries
        self.origin = origin
        self.growsUp = growsUp
    }

    func showPopup<Content: View>(at origin: CGPoint, @ViewBuilder _ content: () -> Content) {
        entries = []
        popup = AnyView(content())
        popupOrigin = origin
    }

    /// Puts the menu away, and the card under it if there is no menu.
    func dismiss() {
        if !entries.isEmpty, popup != nil { return closeMenu() }
        entries = []
        popup = nil
    }

    /// Puts only the menu away, leaving any card it came from.
    func closeMenu() {
        entries = []
    }
}

/// Draws the open menu over everything else in the window. Put one at the
/// root of each window's view tree, above the content.
struct MenuLayer: View {
    @Environment(MenuHost.self) private var menus

    var body: some View {
        if menus.isOpen {
            GeometryReader { geo in
                // Copied out first: alignment guides run in closures that may
                // not reach back into the host or the proxy.
                let bounds = geo.size
                ZStack(alignment: .topLeading) {
                    // A click anywhere outside the card puts the menu away and
                    // does nothing else, as a system menu would.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { menus.dismiss() }

                    if let popup = menus.popup {
                        placed(popup, at: menus.popupOrigin, growsUp: false, in: bounds)
                    }
                    if !menus.entries.isEmpty {
                        if menus.popup != nil {
                            // Over a card: a click on the card away from the
                            // menu only puts the menu away.
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { menus.closeMenu() }
                        }
                        placed(AnyView(MenuCard(entries: menus.entries) { menus.dismiss() }),
                               at: menus.origin, growsUp: menus.growsUp, in: bounds)
                    }
                }
                .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
            .onExitCommand { menus.dismiss() }
        }
    }

    /// A card kept inside the window, its top-left at `origin` (its bottom
    /// there when `growsUp`).
    private func placed(_ card: AnyView, at origin: CGPoint, growsUp: Bool, in bounds: CGSize) -> some View {
        let inset = Theme.floatInset
        return card
            .fixedSize()
            .alignmentGuide(.leading) { d in
                -min(origin.x, max(bounds.width - d.width - inset, 0))
            }
            .alignmentGuide(.top) { d in
                let top = growsUp ? origin.y - d.height : origin.y
                return -min(max(top, inset), max(bounds.height - d.height - inset, 0))
            }
    }
}

private struct MenuCard: View {
    let entries: [MenuEntry]
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entries) { entry in
                switch entry.kind {
                case .separator:
                    Rectangle().fill(Theme.border).frame(height: Theme.hairline).padding(.vertical, 4)
                case .header(let title):
                    Text(title)
                        .font(ThemeFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6)
                        .frame(height: Theme.control, alignment: .bottomLeading)
                case let .item(title, icon, checked, disabled, action):
                    MenuItemRow(title: title, icon: icon, checked: checked, disabled: disabled) {
                        close()
                        action()
                    }
                }
            }
        }
        .padding(Theme.menuPad)
        .frame(minWidth: Theme.menuMinWidth, alignment: .leading)
        .floatingPanel(corner: Theme.radiusMenu)
    }
}

private struct MenuItemRow: View {
    let title: String
    let icon: Icon?
    let checked: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    IconView(icon, size: 15)
                } else {
                    IconView(.check, size: 13)
                        .opacity(checked ? 1 : 0)
                }
                Text(title)
                    .font(ThemeFont.label)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(disabled ? Theme.textTertiary.opacity(0.6) : Theme.textPrimary)
            .padding(.horizontal, 6)
            .frame(height: Theme.control)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                .fill(hovering && !disabled ? Theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// A named choice that opens the app's menu just under itself. Shaped like a
/// slider row, name above and control across the panel, so it keeps the same
/// line down the column.
struct MenuRow: View {
    let label: String
    /// What the control reads when shut: the choice in force.
    let value: String
    let entries: () -> [MenuEntry]
    var isEnabled = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            MenuField(value: value, entries: entries, isEnabled: isEnabled)
        }
        .padding(.vertical, 2)
    }
}

/// The control of a `MenuRow` on its own, for choices sitting side by side
/// under one name.
struct MenuField: View {
    /// What the control reads when shut: the choice in force.
    let value: String
    let entries: () -> [MenuEntry]
    var isEnabled = true
    /// `Theme.control` to sit level with number fields in one row.
    var height: CGFloat = Theme.panelRow + 4

    @Environment(MenuHost.self) private var menus
    @State private var frame: CGRect = .zero
    @State private var hovering = false

    var body: some View {
        // A real button rather than a tap gesture, so a click always lands
        // and accessibility can press it.
        Button {
            // Flush with the control's left edge and just under it, so the
            // menu reads as having come out of it.
            menus.show(entries(), at: CGPoint(x: frame.minX, y: frame.maxY + 4))
        } label: {
            HStack(spacing: 6) {
                Text(value)
                    .font(ThemeFont.label)
                    .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconView(.chevronDown, size: 13)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(hovering && isEnabled ? Theme.panelHover : Theme.panelRaised))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    }
}

extension View {
    /// Opens the app's menu at the pointer on a right-click or control-click.
    func rightClickMenu(_ entries: @escaping () -> [MenuEntry]) -> some View {
        modifier(RightClickMenu(entries: entries))
    }
}

private struct RightClickMenu: ViewModifier {
    let entries: () -> [MenuEntry]
    @Environment(MenuHost.self) private var menus

    func body(content: Content) -> some View {
        content.overlay(RightClickCatcher { point in menus.show(entries(), at: point) })
    }
}

/// A transparent view that takes right-clicks and lets every other click
/// through to what is under it. SwiftUI has no right-click gesture of its own
/// besides `contextMenu`, which is the system menu.
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.onRightClick = onRightClick
    }

    final class Catcher: NSView {
        var onRightClick: (CGPoint) -> Void = { _ in }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary = event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) { report(event) }

        override func mouseDown(with event: NSEvent) { report(event) }

        private func report(_ event: NSEvent) {
            guard let content = window?.contentView else { return }
            let p = content.convert(event.locationInWindow, from: nil)
            // SwiftUI's global space has its origin at the top-left.
            onRightClick(CGPoint(x: p.x, y: content.isFlipped ? p.y : content.bounds.height - p.y))
        }
    }
}
