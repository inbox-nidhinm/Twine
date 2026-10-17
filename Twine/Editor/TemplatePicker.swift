import SwiftUI
import MotionModel
import MotionEvaluation
import MotionEditing
import MotionRendering
import Theme

/// Every template, in headed groups, each on a tile showing it with plain
/// cards; under the pointer a tile plays its loop. Picking one adds it
/// (the selected pictures going into its slots).
struct TemplatePicker: View {
    let pick: (TemplateInfo) -> Void
    let close: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    @State private var search = ""
    @FocusState private var searching: Bool

    /// The templates whose name or group holds what is typed.
    private var matching: [TemplateInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Templates.library }
        return Templates.library.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.group.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(title: "Templates") {
                IconButton(icon: .close, help: "Back to actions") { close() }
            }
            VStack(alignment: .leading, spacing: Theme.panelPad) {
                TextField("Search", text: $search)
                    .textFieldStyle(.plain)
                    .font(ThemeFont.label)
                    .focused($searching)
                    .padding(.horizontal, 8)
                    .frame(height: Theme.control)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(Theme.panelRaised))
                    .focusRing(searching)
                    .onSubmit { if let first = matching.first { pick(first) } }
                    .onAppear { searching = true }
                if matching.isEmpty {
                    Text("No templates")
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(TemplateGroup.allCases, id: \.self) { group in
                    let shown = matching.filter { $0.group == group }
                    if !shown.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(ThemeFont.labelStrong)
                                .foregroundStyle(Theme.textPrimary)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(shown) { info in
                                    TemplateChoice(info: info) { pick(info) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.panelPad)
            .padding(.bottom, Theme.panelPad)
        }
    }
}

/// A template on a tile, its name under it.
private struct TemplateChoice: View {
    let info: TemplateInfo
    let action: () -> Void

    @State private var hovering = false
    @State private var started = Date()

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if hovering {
                        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                            poster(TemplatePosters.image(info.kind, phase: context.date.timeIntervalSince(started) / TemplatePosters.period))
                        }
                    } else {
                        poster(TemplatePosters.poster(info.kind))
                    }
                }
                .aspectRatio(Double(TemplatePosters.width) / Double(TemplatePosters.height), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusWell))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusWell).strokeBorder(hovering ? Theme.textTertiary : .clear, lineWidth: 1))
                Text(info.name)
                    .font(ThemeFont.label)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { started = Date() }
            hovering = inside
        }
        .help("Adds \(info.name), filling the frame, with the selected pictures in its slots.")
    }

    @ViewBuilder private func poster(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 2).resizable()
        } else {
            Theme.panelRaised
        }
    }
}

/// The tiles' pictures: each template drawn with plain cards through the
/// same renderer exports use, small. Stills are kept; a playing tile is
/// drawn afresh each frame.
@MainActor
enum TemplatePosters {
    static let width = 320
    static let height = 200
    /// How long a tile takes to play one loop.
    static let period = 6.0
    /// Where in its loop a still shows it, a little way in.
    static let rest = 0.12

    private static let renderer = OffscreenRenderer(pixelWidth: width, pixelHeight: height)
    private static var stills: [TemplateKind: CGImage] = [:]

    static func poster(_ kind: TemplateKind) -> CGImage? {
        if let known = stills[kind] { return known }
        let made = image(kind, phase: rest)
        stills[kind] = made
        return made
    }

    static func image(_ kind: TemplateKind, phase: Double) -> CGImage? {
        let composition = Composition(width: width, height: height)
        var frame = Templates.frame(kind, filling: composition)
        frame.look = ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [Fill(paint: .color(RGBA(0.1, 0.1, 0.11)))])
        frame.template?.pose = phase - phase.rounded(.down)
        return renderer?.image(of: evaluateDesign(Project(composition: composition, layers: [frame])))
    }
}
