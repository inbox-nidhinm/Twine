import SwiftUI
import MotionModel
import Theme

/// Design mode's bar: the tools, straight on the floating bar. One hover
/// highlight slides from tool to tool under the pointer rather than each
/// lighting up by itself (the user's choice, 30 September 2026, with the
/// tray behind the tools, which Flip needed to part two rows, taken away).
struct ToolBar: View {
    @Bindable var editor: EditorModel

    @Environment(MenuHost.self) private var menus
    @State private var chevronFrame: CGRect = .zero
    /// What the pointer is over: a tool, or the shapes chevron.
    @State private var hovered: Spot?
    /// Where the highlight sits: the spot hovered, or after the pointer
    /// leaves, the last one, while it fades there.
    @State private var place: Spot?
    /// Each spot's box in the bar.
    @State private var frames: [Spot: CGRect] = [:]

    private enum Spot: Hashable {
        case tool(Tool), chevron
    }

    nonisolated private static let space = "toolbar"

    var body: some View {
        HStack(spacing: Theme.trayPad) {
            tool(.select)
            tool(.frame)
            HStack(spacing: 0) {
                tool(editor.lastShape)
                shapeChevron
            }
            tool(.pen)
            tool(.text)
        }
        .coordinateSpace(.named(Self.space))
        // One highlight for the whole row, moved to the spot under the
        // pointer. A highlight per tool, handed on by a matched geometry
        // effect, stuck going right to left: the one fading out came later
        // in the row and pulled the new one back to itself.
        .background(alignment: .topLeading) {
            if let place, let box = frames[place] {
                RoundedRectangle(cornerRadius: radius(place))
                    .fill(Theme.panelRaised)
                    .frame(width: box.width, height: box.height)
                    .offset(x: box.minX, y: box.minY)
                    .opacity(hovered == nil ? 0 : 1)
            }
        }
        .padding(Theme.trayPad + Theme.barPad)
        .floatingPanel()
    }

    private func tool(_ tool: Tool) -> some View {
        BarButton(icon: tool.icon, help: "\(tool.title) (\(tool.key))", isOn: editor.tool == tool,
                  size: Theme.modeButton, iconBox: Theme.icon, hoverFill: .clear) {
            pick(tool)
        }
        .onHover { hover(.tool(tool), $0) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[.tool(tool)] = $0 }
    }

    private func radius(_ spot: Spot) -> CGFloat {
        spot == .chevron ? Theme.radiusRow : Theme.radius(forButton: Theme.modeButton)
    }

    /// Moving from one spot to the next slides the highlight there; coming
    /// onto the bar, it appears where the pointer is rather than sliding in
    /// from where it last faded. Leaving waits a moment, since the next
    /// spot's arrival may come just after, and only then fades it, if
    /// nothing has taken it since.
    private func hover(_ spot: Spot, _ inside: Bool) {
        if inside {
            if hovered == nil {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { place = spot }
            }
            withAnimation(Theme.hoverGlide) {
                place = spot
                hovered = spot
            }
        } else if hovered == spot {
            DispatchQueue.main.asyncAfter(deadline: .now() + Theme.hoverLinger) {
                guard hovered == spot else { return }
                withAnimation(Theme.hoverGlide) { hovered = nil }
            }
        }
    }

    private func pick(_ tool: Tool) {
        editor.tool = tool
        if tool.isShape { editor.lastShape = tool }
    }

    /// Outside the tool's square, so it never lights up with the accent when
    /// that tool is in hand. The menu it raises names the shapes, since five
    /// bare glyphs would make you guess.
    private var shapeChevron: some View {
        let chevronGlyph: CGFloat = 13
        return Button {
            let entries = Tool.shapes.map { shape in
                MenuEntry.item("\(shape.title)   \(shape.key)", checked: editor.tool == shape) { pick(shape) }
            }
            menus.show(entries, at: CGPoint(x: chevronFrame.minX - Theme.modeButton, y: chevronFrame.minY - 6),
                       growsUp: true)
        } label: {
            IconView(.chevronDown, size: chevronGlyph)
                .foregroundStyle(hovered == .chevron ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: chevronGlyph + (Theme.modeButton - Theme.icon) / 2, height: Theme.modeButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover(.chevron, $0) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { frames[.chevron] = $0 }
        .help("More shapes")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { chevronFrame = $0 }
    }
}
