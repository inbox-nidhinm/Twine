import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Home's New from Template card: every template, as Animate's picker
/// shows them, four across; picking one makes a project holding it.
struct TemplateGalleryCard: View {
    let library: Library

    var body: some View {
        ZStack {
            Theme.badge
                .contentShape(Rectangle())
                .onTapGesture { library.pickingTemplate = false }

            ScrollView {
                TemplatePicker(pick: { library.newProject(from: $0.kind) },
                               close: { library.pickingTemplate = false },
                               across: 4, closeHelp: "Close (Esc)")
            }
            .frame(width: Theme.templateGalleryWidth, height: Theme.templateGalleryHeight)
            .floatingPanel()
            .onExitCommand { library.pickingTemplate = false }
        }
    }
}
