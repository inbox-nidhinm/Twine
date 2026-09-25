import SwiftUI
import MotionModel
import Theme

/// Design mode's bar: the tools, on a tray of their own. They are modes rather
/// than actions, which the big square buttons and the lighter tray say without
/// a label.
struct ToolBar: View {
    @Bindable var editor: EditorModel

    @Environment(MenuHost.self) private var menus
    @State private var chevronFrame: CGRect = .zero
    @State private var chevronHover = false

    var body: some View {
        HStack(spacing: Theme.trayPad) {
            tool(.select)
            HStack(spacing: 0) {
                tool(editor.lastShape)
                shapeChevron
            }
            tool(.pen)
            tool(.text)
        }
        .padding(Theme.trayPad)
        .background(RoundedRectangle(cornerRadius: Theme.radiusTray).fill(Theme.panelRaised))
        .padding(Theme.barPad)
        .floatingPanel()
    }

    private func tool(_ tool: Tool) -> some View {
        BarButton(icon: tool.icon, help: tool.isAvailable ? "\(tool.title) (\(tool.key))" : "\(tool.title) (coming soon)",
                  isOn: editor.tool == tool, disabled: !tool.isAvailable,
                  size: Theme.modeButton, iconBox: Theme.icon, hoverFill: Theme.panelHover) {
            pick(tool)
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
                .foregroundStyle(chevronHover ? Theme.textPrimary : Theme.textTertiary)
                .frame(width: chevronGlyph + (Theme.modeButton - Theme.icon) / 2, height: Theme.modeButton)
                .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                    .fill(chevronHover ? Theme.panelHover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { chevronHover = $0 }
        .help("More shapes")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { chevronFrame = $0 }
    }
}
