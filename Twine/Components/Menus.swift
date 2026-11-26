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
    /// An item's keys, shown at its end, as a system menu shows them.
    var shortcut: String? = nil

    static func item(_ title: String, icon: Icon? = nil, checked: Bool = false, disabled: Bool = false,
                     shortcut: String? = nil, _ action: @escaping () -> Void) -> MenuEntry {
        MenuEntry(kind: .item(title: title, icon: icon, checked: checked, disabled: disabled, action: action),
                  shortcut: shortcut)
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

    /// The row of the open menu that the pointer or the arrow keys are on,
    /// as its place in `entries`: the one Return picks.
    var highlighted: Int?

    /// The card's frame in the window, from its top-left, told by the layer
    /// that draws it. Not watched: nothing is drawn from it.
    @ObservationIgnored var popupFrame: CGRect = .zero
    /// Where the card just closed by a press outside it had been raised, so
    /// the control that raised it, if the press was on it, does not raise
    /// it straight back.
    @ObservationIgnored private var justClosed: CGPoint?
    /// Asked on a press over the canvas: true keeps the card up, as a
    /// gradient's card stays while its line is dragged there.
    @ObservationIgnored private var popupStays: (() -> Bool)?

    /// A card alone is up that stays for presses on the canvas.
    var staysOverCanvas: Bool { popup != nil && entries.isEmpty && popupStays?() == true }

    /// A menu, over the card that is up if any: nothing outside a menu can
    /// be clicked while it is up, as with a system menu.
    func show(_ entries: [MenuEntry], at origin: CGPoint, growsUp: Bool = false) {
        self.entries = entries
        self.origin = origin
        self.growsUp = growsUp
        highlighted = nil
    }

    func showPopup<Content: View>(at origin: CGPoint, staysOverCanvas: (() -> Bool)? = nil,
                                  @ViewBuilder _ content: () -> Content) {
        // The press that closed the card was on the control that raises
        // it: the click closes it, as a second click on a control should.
        if let closed = justClosed, closed == origin {
            justClosed = nil
            return
        }
        entries = []
        popup = AnyView(content())
        popupOrigin = origin
        popupFrame = .zero
        popupStays = staysOverCanvas
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
        highlighted = nil
    }

    /// A press in the window at `point` (from its top-left), before it is
    /// handled. A card with no menu over it goes away when the press is
    /// outside it, and the press carries on to whatever it landed on: with
    /// a colour picker open, a click on another swatch, another layer or a
    /// number used to do nothing but close the picker, and took a second
    /// click. A menu still takes the click that closes it, as menus do.
    func pressed(at point: CGPoint, onCanvas: Bool = false) {
        justClosed = nil
        guard popup != nil, entries.isEmpty, popupFrame != .zero, !popupFrame.contains(point) else { return }
        if onCanvas, popupStays?() == true { return }
        justClosed = popupOrigin
        popup = nil
    }

    /// A key pressed while a menu is up: the arrows move through it, Return
    /// or Space picks, a letter goes to the next item starting with it, and
    /// Escape closes it. Every key is the menu's while it is up, so none
    /// reaches the canvas behind it (Delete used to delete the selection).
    /// False when no menu is up, and the key is someone else's.
    func key(_ event: NSEvent) -> Bool {
        guard !entries.isEmpty else { return false }
        switch event.keyCode {
        case 125: move(1)
        case 126: move(-1)
        case 36, 76, 49:
            if let at = highlighted, entries.indices.contains(at), case .item(_, _, _, false, let action) = entries[at].kind {
                dismiss()
                action()
            }
        case 53: dismiss()
        default:
            if let letter = event.charactersIgnoringModifiers?.lowercased(), letter.count == 1, letter != " " {
                let order = Array((highlighted ?? -1) + 1 ..< entries.count) + Array(0 ..< min((highlighted ?? -1) + 1, entries.count))
                highlighted = order.first { title(at: $0)?.lowercased().hasPrefix(letter) == true } ?? highlighted
            }
        }
        return true
    }

    /// The title of the item at `index` when it can be picked.
    private func title(at index: Int) -> String? {
        guard entries.indices.contains(index), case .item(let title, _, _, false, _) = entries[index].kind else { return nil }
        return title
    }

    private func move(_ by: Int) {
        let pickable = entries.indices.filter { title(at: $0) != nil }
        guard !pickable.isEmpty else { return }
        guard let now = highlighted, let at = pickable.firstIndex(of: now) else {
            highlighted = by > 0 ? pickable.first : pickable.last
            return
        }
        highlighted = pickable[(at + by + pickable.count) % pickable.count]
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
                    // A click anywhere outside a menu puts it away and does
                    // nothing else, as a system menu would. A card alone has
                    // no such ground: a press outside it closes it from the
                    // window (`MenuHost.pressed`) and carries on.
                    if !menus.entries.isEmpty && menus.popup == nil {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { menus.dismiss() }
                    }

                    // A card alone still needs something the size of the
                    // window beside it: alignment guides place a view
                    // against its siblings, and with none the card sat in
                    // the window's top-left corner (since cards began
                    // letting presses through, v0.2.63). It takes no presses.
                    if menus.popup != nil && menus.entries.isEmpty {
                        Color.clear.allowsHitTesting(false)
                    }
                    if let popup = menus.popup {
                        placed(AnyView(popup.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                                           action: { menus.popupFrame = $0 }),
                               at: menus.popupOrigin, growsUp: false, in: bounds)
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

    @Environment(MenuHost.self) private var menus

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                switch entry.kind {
                case .separator:
                    Rectangle().fill(Theme.rule).frame(height: Theme.hairline).padding(.vertical, Theme.space4)
                case .header(let title):
                    Text(title)
                        .font(ThemeFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, Theme.space6)
                        .frame(height: Theme.control, alignment: .bottomLeading)
                case let .item(title, icon, checked, disabled, action):
                    // One highlight for the pointer and the arrow keys.
                    MenuItemRow(title: title, icon: icon, checked: checked, disabled: disabled, shortcut: entry.shortcut,
                                lit: menus.highlighted == index,
                                hover: { inside in
                                    if inside { menus.highlighted = index } else if menus.highlighted == index { menus.highlighted = nil }
                                }) {
                        close()
                        action()
                    }
                }
            }
        }
        .padding(Theme.menuPad)
        .frame(minWidth: Theme.menuMinWidth, alignment: .leading)
        .floatingPanel(corner: Theme.radiusMenu, fill: Theme.dropdown)
    }
}

private struct MenuItemRow: View {
    let title: String
    let icon: Icon?
    let checked: Bool
    let disabled: Bool
    var shortcut: String? = nil
    /// Whether the pointer or the arrow keys are on this row.
    var lit = false
    var hover: (Bool) -> Void = { _ in }
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.space6) {
                if let icon {
                    IconView(icon, size: Theme.iconRow)
                } else {
                    IconView(.check, size: Theme.iconSmall)
                        .opacity(checked ? 1 : 0)
                }
                Text(title)
                    .font(ThemeFont.label)
                    .lineLimit(1)
                Spacer(minLength: shortcut == nil ? 0 : Theme.space20)
                if let shortcut {
                    Text(shortcut)
                        .font(ThemeFont.label)
                        .foregroundStyle(lit && !disabled ? Theme.textPrimary.opacity(0.8) : Theme.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(disabled ? Theme.textTertiary.opacity(0.6) : Theme.textPrimary)
            .padding(.horizontal, Theme.space6)
            .frame(height: Theme.control)
            .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                .fill(lit && !disabled ? Theme.accent : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover(perform: hover)
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
        VStack(alignment: .leading, spacing: Theme.space6) {
            Text(label)
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            MenuField(value: value, entries: entries, isEnabled: isEnabled)
        }
        .padding(.vertical, Theme.space2)
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
    /// A `PanelButton`'s grounds and words, to sit among them, as Home's
    /// order menu does beside its New buttons.
    var quiet = false

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
            HStack(spacing: Theme.space6) {
                Text(value)
                    .font(ThemeFont.label)
                    .foregroundStyle(!isEnabled ? Theme.textTertiary : quiet ? Theme.textSecondary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconView(.chevronDown, size: Theme.iconSmall)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.space8)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(quiet ? (hovering && isEnabled ? Theme.panelRaised : Theme.panelRaised.opacity(0.5))
                            : hovering && isEnabled ? Theme.panelHover : Theme.panelRaised))
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
