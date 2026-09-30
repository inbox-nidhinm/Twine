import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
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


    var body: some View {
        ZStack(alignment: .bottom) {
            Theme.canvas.grained()
                .ignoresSafeArea()
            CanvasView(controller: controller, editor: editor, insets: canvasInsets)

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
            // In Animate the panels stop above the timeline.
            .padding(.bottom, editor.mode == .animate ? editor.timelineHeight + Theme.floatGap : 0)

            bottomSurface

            if (editor.exports.isExporting || editor.exports.finished != nil) && !editor.showExport {
                ExportStatus(session: editor.exports)
                    .padding(Theme.floatInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            if let notice = editor.notice {
                NoticeCard(notice: notice) { editor.dismissNotice() }
                    .padding(Theme.floatInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }

            if editor.showShortcuts {
                ShortcutsCard { editor.showShortcuts = false }
                    .transition(.opacity)
            }

            if editor.showExport {
                ExportPanel(title: document.name, session: editor.exports, controller: controller, editor: editor,
                            hasSound: !audioClips(store.project).isEmpty)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            MenuLayer()

            if OnboardingState.shared.isShowing {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: OnboardingState.shared.isShowing)
        .animation(.easeOut(duration: 0.18), value: editor.showLayers)
        .animation(.easeOut(duration: 0.18), value: editor.showInspector)
        .animation(.easeOut(duration: 0.18), value: editor.mode)
        .animation(.easeOut(duration: 0.15), value: editor.showShortcuts)
        .animation(.easeOut(duration: 0.18), value: editor.notice)
        .animation(Theme.exportFade, value: editor.showExport)
        .animation(.easeOut(duration: 0.18), value: editor.exports.isExporting || editor.exports.finished != nil)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        // Every number field in the window, its cards and menus included,
        // undoes a drag as one step.
        .environment(\.scrubbing, controller.scrubbing)
    }

    /// Design mode floats the tools in a bar centred under the canvas,
    /// between the panels; Animate mode swaps it for the timeline, which
    /// runs the full width of the window with the panels above it.
    @ViewBuilder private var bottomSurface: some View {
        switch editor.mode {
        case .design:
            ToolBar(editor: editor)
                .padding(.bottom, Theme.floatInset)
                .padding(.leading, leftGutter)
                .padding(.trailing, rightGutter)
                .transition(.opacity)
        case .animate:
            TimelinePanel(controller: controller, editor: editor)
                .frame(height: editor.timelineHeight)
                .frame(maxWidth: .infinity)
                .floatingPanel()
                .overlay(alignment: .top) { timelineGrip }
                .padding(Theme.floatInset)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// The timeline's top edge, dragged to make it taller or shorter.
    private var timelineGrip: some View {
        Color.clear
            .frame(height: Theme.resizeEdge)
            .contentShape(Rectangle())
            .background(CursorArea(cursor: Cursors.resizeVertical))
            // SwiftUI's own pointer as well, since the window's SwiftUI puts
            // its arrow back over a cursor rect as the pointer moves.
            .pointerStyle(.image(Image(nsImage: Cursors.resizeVertical.image), hotSpot: .center))
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { g in
                    if gripStart == nil { gripStart = editor.timelineHeight }
                    let range = EditorModel.timelineHeightRange
                    editor.timelineHeight = min(max((gripStart ?? 260) - g.translation.height, range.lowerBound), range.upperBound)
                }
                .onEnded { _ in
                    gripStart = nil
                    editor.saveTimelineHeight()
                })
            .offset(y: -3)
    }

    @State private var gripStart: CGFloat?

    private var leftGutter: CGFloat {
        editor.showLayers ? Theme.floatInset + Theme.panelWidth : Theme.floatInset
    }

    private var rightGutter: CGFloat {
        editor.showInspector ? Theme.floatInset + Theme.panelWidth : Theme.floatInset
    }

    /// What the panels and the bottom surface cover, so a fitted composition
    /// lands in the space that is actually visible.
    private var canvasInsets: EdgeInsets {
        let bottom = editor.mode == .animate ? editor.timelineHeight : Theme.barHeight
        return EdgeInsets(top: Theme.floatInset,
                          leading: leftGutter,
                          bottom: bottom + Theme.floatInset * 2,
                          trailing: rightGutter)
    }
}
