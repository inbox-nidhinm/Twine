import SwiftUI
import MotionModel
import MotionEditing
import Theme

/// Home's New from Template screen: a panel of the template groups beside
/// a panel of the chosen group's templates, each on a tile that plays its
/// loop under the pointer. Picking one makes a project holding it.
struct TemplateGalleryCard: View {
    let library: Library

    @State private var group: TemplateGroup = .perspective
    @State private var hoveredGroup: TemplateGroup?

    var body: some View {
        GeometryReader { window in
            let width = window.size.width * Theme.templateGalleryWidthShare
            ZStack {
                // The app's own ground, as onboarding has: nothing behind
                // shows through.
                Theme.canvas
                    .grained()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)

                HStack(alignment: .top, spacing: Theme.templateGalleryGap) {
                    groups
                    templates(width: max(width - Theme.templateSidebarWidth - Theme.templateGalleryGap, 0))
                }
                .frame(width: width, height: window.size.height * Theme.templateGalleryHeightShare)
                .onExitCommand(perform: close)
            }
        }
    }

    private func close() { library.pickingTemplate = false }

    // MARK: Groups

    private var groups: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Templates")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, Theme.panelPad)
                .frame(maxWidth: .infinity, minHeight: Theme.templateGalleryHeader, maxHeight: Theme.templateGalleryHeader,
                       alignment: .leading)
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(TemplateGroup.allCases, id: \.self) { row($0) }
                }
                .padding(.vertical, Theme.rowGap * 2)
            }
        }
        .frame(width: Theme.templateSidebarWidth)
        .frame(maxHeight: .infinity)
        .floatingPanel()
    }

    /// A group's line, as Home's sidebar draws its folders.
    private func row(_ g: TemplateGroup) -> some View {
        Button { group = g } label: {
            Text(g.title)
                .font(ThemeFont.label)
                .lineLimit(1)
                .foregroundStyle(g == group ? Theme.textPrimary : Theme.textSecondary)
                .padding(.horizontal, Theme.panelPad)
                .frame(maxWidth: .infinity, minHeight: Theme.listRow, maxHeight: Theme.listRow, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Theme.radiusRow)
                    .fill(g == group ? Theme.panelRaised : hoveredGroup == g ? Theme.rowHover : .clear)
                    .padding(.horizontal, Theme.rowGap))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { hoveredGroup = g } else if hoveredGroup == g { hoveredGroup = nil }
        }
    }

    // MARK: Templates

    /// The chosen group's tiles in a panel `width` wide: as many across as
    /// fit at their own width, sharing out what is left.
    private func templates(width: CGFloat) -> some View {
        let inside = width - Theme.templateGalleryPad * 2
        let across = max(Int((inside + Theme.templateTileGap) / (Theme.templateTileWidth + Theme.templateTileGap)), 1)
        let tile = max((inside - Theme.templateTileGap * CGFloat(across - 1)) / CGFloat(across), 1)
        let columns = Array(repeating: GridItem(.fixed(tile), spacing: Theme.templateTileGap), count: across)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.title)
                    .displayTitle(18)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                IconButton(icon: .close, help: "Close (Esc)", action: close)
            }
            .padding(.leading, Theme.templateGalleryPad)
            .padding(.trailing, Theme.sheetCloseInset)
            .frame(height: Theme.templateGalleryHeader)
            Rectangle().fill(Theme.border).frame(height: Theme.hairline)
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.templateTileGap) {
                    ForEach(Templates.library.filter { $0.group == group }) { info in
                        GalleryTile(info: info, width: tile) { library.newProject(from: info.kind) }
                    }
                }
                .padding(Theme.templateGalleryPad)
            }
            // Opens at the top, and a new group starts at its top: laid out
            // once at no width first, the grid otherwise opened part way down.
            .defaultScrollAnchor(.top)
            .id(group)
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .floatingPanel()
    }
}

/// A template on a tile: its picture, drawn on the tile itself, over its
/// name. Under the pointer it plays its loop.
private struct GalleryTile: View {
    let info: TemplateInfo
    /// The tile's width; it keeps its shape, and its picture is square.
    let width: CGFloat
    let action: () -> Void

    private var side: CGFloat { max(width - Theme.templateTileInset * 2, 1) }
    private var style: TemplatePosters.Style { .gallery(side: side) }

    @State private var hovering = false
    @State private var image: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.radiusCard)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 2).resizable()
                    } else {
                        Color.clear
                    }
                }
                // Kept off the tile's edges, as the name is.
                .frame(width: side, height: side)
                .padding([.top, .horizontal], Theme.templateTileInset)
                Spacer(minLength: 0)
                Text(info.name)
                    .font(ThemeFont.tileName)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.templateTileInset)
                    .padding(.bottom, Theme.templateTileInset)
            }
            .frame(width: width, height: width * Theme.templateTileHeight / Theme.templateTileWidth, alignment: .topLeading)
            .background(shape.fill(hovering ? Theme.templateTileHover : Theme.templateTile))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // The still, then, under the pointer, the loop playing until it leaves.
        .task(id: TileState(hovering: hovering, style: style)) {
            guard hovering else {
                image = await TemplatePosters.poster(info.kind, style: style)
                return
            }
            let started = Date()
            while !Task.isCancelled {
                if let frame = await TemplatePosters.image(info.kind, phase: Date().timeIntervalSince(started) / TemplatePosters.period,
                                                           style: style) {
                    image = frame
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        .help("Makes a new project holding \(info.name), as long as one loop of it.")
    }
}

/// What a tile's picture depends on: whether it plays, and its size.
private struct TileState: Equatable {
    let hovering: Bool
    let style: TemplatePosters.Style
}
