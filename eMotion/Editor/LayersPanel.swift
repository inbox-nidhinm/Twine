import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// The left panel: the project's name in the strip beside the traffic lights,
/// then the layer tree. The tree keeps groupings; the timeline, a separate
/// surface, is only for keyframes.
struct LayersPanel: View {
    let document: ProjectDocument
    let store: ProjectStore
    @Bindable var editor: EditorModel

    @State private var renaming = false
    @State private var draft = ""
    @State private var nameHover = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PanelDivider()
            SectionHeader(title: "Layers")
            // Rows arrive with the first layer tools in milestone 3. Until then
            // the list is what an empty project's list is: empty.
            ScrollView {
                LazyVStack(spacing: Theme.rowGap) {}
            }
            .frame(maxHeight: .infinity)
        }
        // In the empty strip the header keeps clear of the traffic lights, so
        // it sits over the layout rather than in it.
        .overlay(alignment: .topTrailing) {
            IconButton(icon: .home, help: "Home (⇧⌘H)") {
                HomeWindowController.shared.showWindow(nil)
            }
            .padding(.trailing, Theme.panelPad - 4)
            .padding(.top, Theme.panelPad - 6)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            if renaming {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(ThemeFont.title)
                    .foregroundStyle(Theme.textPrimary)
                    .focused($nameFocused)
                    .onAppear { DispatchQueue.main.async { nameFocused = true } }
                    .onSubmit(commitName)
                    .onExitCommand { renaming = false }
                    .onChange(of: nameFocused) { _, now in if !now, renaming { commitName() } }
            } else {
                Text(document.name)
                    .font(ThemeFont.title)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    // The hover fill hugs the word and bleeds back out, so the
                    // header does not shift as the pointer crosses it.
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                        .fill(nameHover ? Theme.rowHover : .clear))
                    .padding(.horizontal, -4)
                    .contentShape(Rectangle())
                    .onHover { nameHover = $0 }
                    .help("Rename")
                    // High priority, or the window drag on the header takes the click.
                    .highPriorityGesture(TapGesture().onEnded {
                        draft = document.name
                        renaming = true
                    })
            }
            Text(summary)
                .font(ThemeFont.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.panelPad)
        // Clears the traffic lights, which sit inside this panel.
        .padding(.top, 44)
        .padding(.bottom, Theme.panelPad)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    /// The composition in one line: size, rate, length.
    private var summary: String {
        let c = store.project.composition
        return "\(c.width) × \(c.height) · \(c.frameRate.label) fps · \(TimeFormat.seconds(c.duration))"
    }

    private func commitName() {
        renaming = false
        document.rename(to: draft)
    }
}

enum TimeFormat {
    /// `5s`, `2.5s`, `1:05.25`.
    static func seconds(_ t: Double) -> String {
        let minutes = Int(t / 60)
        let rest = t - Double(minutes * 60)
        var s = String(format: "%.2f", rest)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if minutes == 0 { return s + "s" }
        return "\(minutes):" + (rest < 10 ? "0" : "") + s
    }

    /// `0:02.50`, the playhead readout.
    static func clock(_ t: Double) -> String {
        let minutes = Int(t / 60)
        let rest = t - Double(minutes * 60)
        return String(format: "%d:%05.2f", minutes, rest)
    }
}
