import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// One project window: the canvas full-bleed underneath, and everything else
/// floating over it. Hiding a panel hands its space back to the canvas rather
/// than reflowing columns.
struct EditorView: View {
    let document: ProjectDocument
    let store: ProjectStore
    @Bindable var editor: EditorModel
    let controller: EditorController

    @Environment(MenuHost.self) private var menus

    /// The height the timeline card takes in Animate mode.
    static let timelineHeight: CGFloat = 240

    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.grained()
                .ignoresSafeArea()
            CanvasView(controller: controller, project: store.project, time: editor.time,
                       selection: controller.selection, tool: editor.tool, insets: canvasInsets)

            HStack(alignment: .top, spacing: 0) {
                if editor.showLayers {
                    LayersPanel(document: document, store: store, editor: editor, controller: controller)
                        .frame(width: Theme.panelWidth)
                        .frame(maxHeight: .infinity)
                        .floatingPanel()
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                Spacer(minLength: Theme.floatGap)
                if editor.showInspector {
                    InspectorPanel(store: store, editor: editor, controller: controller)
                        .frame(width: Theme.panelWidth)
                        .frame(maxHeight: .infinity)
                        .floatingPanel()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .padding(Theme.floatInset)

            bottomSurface
                .padding(.bottom, Theme.floatInset)
                .padding(.leading, leftGutter)
                .padding(.trailing, rightGutter)

            MenuLayer()
        }
        .animation(.easeOut(duration: 0.18), value: editor.showLayers)
        .animation(.easeOut(duration: 0.18), value: editor.showInspector)
        .animation(.easeOut(duration: 0.18), value: editor.mode)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    /// Design mode floats the tools in a bar centred under the canvas;
    /// Animate mode swaps it for the timeline, which runs the full width
    /// between the panels.
    @ViewBuilder private var bottomSurface: some View {
        switch editor.mode {
        case .design:
            ToolBar(editor: editor)
                .transition(.opacity)
        case .animate:
            TimelinePanel(composition: store.project.composition)
                .frame(height: Self.timelineHeight)
                .frame(maxWidth: .infinity)
                .floatingPanel()
                .padding(.horizontal, Theme.floatGap)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var leftGutter: CGFloat {
        editor.showLayers ? Theme.floatInset + Theme.panelWidth : Theme.floatInset
    }

    private var rightGutter: CGFloat {
        editor.showInspector ? Theme.floatInset + Theme.panelWidth : Theme.floatInset
    }

    /// What the panels and the bottom surface cover, so a fitted composition
    /// lands in the space that is actually visible.
    private var canvasInsets: EdgeInsets {
        let bottom = editor.mode == .animate ? Self.timelineHeight : Theme.barHeight
        return EdgeInsets(top: Theme.floatInset,
                          leading: leftGutter,
                          bottom: bottom + Theme.floatInset * 2,
                          trailing: rightGutter)
    }
}
