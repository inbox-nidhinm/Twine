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
    /// Tiles across: two in the inspector, more on Home's card.
    var across = 2
    var closeHelp = "Back to actions"

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 8), count: max(across, 1)) }

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
                IconButton(icon: .close, help: closeHelp) { close() }
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

/// A template on a tile, its name under it. Its picture is drawn away from
/// the main thread (`TemplatePosters`), never while the view is built:
/// drawing flushes Core Animation, which made SwiftUI build the tile again
/// mid-way and stopped the app.
private struct TemplateChoice: View {
    let info: TemplateInfo
    let action: () -> Void

    @State private var hovering = false
    @State private var image: CGImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 2).resizable()
                    } else {
                        Theme.panelRaised
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
        .onHover { hovering = $0 }
        // The still, then, under the pointer, the loop playing until it leaves.
        .task(id: hovering) {
            guard hovering else {
                image = await TemplatePosters.poster(info.kind)
                return
            }
            let started = Date()
            while !Task.isCancelled {
                if let frame = await TemplatePosters.image(info.kind, phase: Date().timeIntervalSince(started) / TemplatePosters.period) {
                    image = frame
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        .help("Adds \(info.name), filling the frame, with the selected pictures in its slots.")
    }
}

/// The tiles' pictures: each template drawn with plain cards through the
/// same renderer exports use, small. Stills are kept; a playing tile is
/// drawn afresh each frame.
///
/// Drawn on a queue of its own, as exports are. Drawn on the main thread
/// they came out empty while the picker was still appearing (what Core
/// Animation had been given was not yet handed on to be drawn), and those
/// empty stills were kept: the first tiles showed nothing. A still that
/// comes out empty all the same is drawn again rather than kept.
@MainActor
enum TemplatePosters {
    /// How a still is drawn: the picker's on its dark ground, or Home's
    /// square ones on nothing, so they sit on their tiles.
    nonisolated struct Style: Hashable, Sendable {
        let width: Int
        let height: Int
        let ground: Bool

        static let tile = Style(width: 320, height: 200, ground: true)
        static let gallery = Style(width: Int((Theme.templateTileWidth - Theme.templateTileInset * 2) * 2),
                                   height: Int((Theme.templateTileWidth - Theme.templateTileInset * 2) * 2), ground: false)
    }

    static let width = Style.tile.width
    static let height = Style.tile.height
    /// How long a tile takes to play one loop.
    static let period = 6.0
    /// Where in its loop a still shows it, a little way in.
    static let rest = 0.12

    private static let drawing = Drawing()
    private nonisolated struct Key: Hashable { let kind: TemplateKind; let style: Style }
    private static var stills: [Key: CGImage] = [:]

    static func poster(_ kind: TemplateKind, style: Style = .tile) async -> CGImage? {
        let key = Key(kind: kind, style: style)
        if let known = stills[key] { return known }
        for attempt in 0..<4 {
            if let made = await image(kind, phase: rest, style: style), !Drawing.isBlank(made) {
                stills[key] = made
                return made
            }
            try? await Task.sleep(for: .milliseconds(100 * (attempt + 1)))
            if Task.isCancelled { return nil }
        }
        return nil
    }

    static func image(_ kind: TemplateKind, phase: Double, style: Style = .tile) async -> CGImage? {
        await drawing.image(kind, phase: phase, style: style)
    }

    /// The renderers, one a size, used on one queue only.
    private nonisolated final class Drawing: @unchecked Sendable {
        private let queue = DispatchQueue(label: "Twine.TemplatePosters")
        private var renderers: [Style: OffscreenRenderer] = [:]

        func image(_ kind: TemplateKind, phase: Double, style: Style) async -> CGImage? {
            await withCheckedContinuation { done in
                queue.async { [self] in
                    if renderers[style] == nil { renderers[style] = OffscreenRenderer(pixelWidth: style.width, pixelHeight: style.height) }
                    var composition = Composition(width: style.width, height: style.height)
                    composition.background = Background(isTransparent: !style.ground)
                    var frame = Templates.frame(kind, filling: composition)
                    frame.look = ShapeContent(geometry: .rectangle(cornerRadii: .zero),
                                              fills: style.ground ? [Fill(paint: .color(RGBA(0.1, 0.1, 0.11)))] : [])
                    frame.template?.pose = phase - phase.rounded(.down)
                    done.resume(returning: renderers[style]?.image(of: evaluateDesign(Project(composition: composition, layers: [frame]))))
                }
            }
        }

        /// Whether nothing at all was drawn: no pixel in a sparse grid
        /// over the picture has any strength.
        static func isBlank(_ image: CGImage) -> Bool {
            guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
            let row = image.bytesPerRow, length = CFDataGetLength(data)
            // Alpha is the last byte of each BGRA pixel.
            for y in stride(from: 0, to: image.height, by: 8) {
                for x in stride(from: 0, to: image.width, by: 8) {
                    let i = y * row + x * 4 + 3
                    if i < length, bytes[i] > 0 { return false }
                }
            }
            return true
        }
    }
}
