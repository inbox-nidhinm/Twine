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
    @Namespace private var glide

    private enum Spot: Hashable {
        case tool(Tool), chevron
    }

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
        .padding(Theme.trayPad + Theme.barPad)
        .floatingPanel()
    }

    private func tool(_ tool: Tool) -> some View {
        BarButton(icon: tool.icon, help: "\(tool.title) (\(tool.key))", isOn: editor.tool == tool,
                  size: Theme.modeButton, iconBox: Theme.icon, hoverFill: .clear) {
            pick(tool)
        }
        .background { highlight(.tool(tool), radius: Theme.radius(forButton: Theme.modeButton)) }
        .onHover { hover(.tool(tool), $0) }
    }

    /// The one highlight, under whichever spot the pointer is on (under a
    /// tool in hand too, where its accent covers it, so the slide carries on
    /// across it).
    @ViewBuilder private func highlight(_ spot: Spot, radius: CGFloat) -> some View {
        if hovered == spot {
            RoundedRectangle(cornerRadius: radius)
                .fill(Theme.panelRaised)
                .matchedGeometryEffect(id: "hover", in: glide)
        }
    }

    /// Moving onto a spot slides the highlight there. Leaving waits a moment,
    /// since the next spot's arrival may come just after, and only then fades
    /// it, if nothing has taken it since.
    private func hover(_ spot: Spot, _ inside: Bool) {
        if inside {
            withAnimation(Theme.hoverGlide) { hovered = spot }
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
                .background { highlight(.chevron, radius: Theme.radiusRow) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover(.chevron, $0) }
        .help("More shapes")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { chevronFrame = $0 }
    }
}
