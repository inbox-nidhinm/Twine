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

    private let columns = Array(repeating: GridItem(.fixed(Theme.templateTileWidth), spacing: Theme.templateTileGap), count: 3)

    var body: some View {
        ZStack {
            Theme.badge
                .contentShape(Rectangle())
                .onTapGesture(perform: close)

            HStack(alignment: .top, spacing: Theme.templateGalleryGap) {
                groups
                templates
            }
            .frame(height: Theme.templateGalleryHeight)
            .onExitCommand(perform: close)
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

    private var templates: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                        GalleryTile(info: info) { library.newProject(from: info.kind) }
                    }
                }
                .padding(Theme.templateGalleryPad)
            }
            // A new group starts at its top.
            .id(group)
        }
        .frame(width: Theme.templateGalleryWidth)
        .frame(maxHeight: .infinity)
        .floatingPanel()
    }
}

/// A template on a tile: its picture, drawn on the tile itself, over its
/// name. Under the pointer it plays its loop.
private struct GalleryTile: View {
    let info: TemplateInfo
    let action: () -> Void

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
                .frame(width: Theme.templateTileWidth - Theme.templateTileInset * 2,
                       height: Theme.templateTileWidth - Theme.templateTileInset * 2)
                .padding([.top, .horizontal], Theme.templateTileInset)
                Spacer(minLength: 0)
                Text(info.name)
                    .font(ThemeFont.tileName)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, Theme.templateTileInset)
                    .padding(.bottom, Theme.templateTileInset)
            }
            .frame(width: Theme.templateTileWidth, height: Theme.templateTileHeight, alignment: .topLeading)
            .background(shape.fill(hovering ? Theme.templateTileHover : Theme.templateTile))
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // The still, then, under the pointer, the loop playing until it leaves.
        .task(id: hovering) {
            guard hovering else {
                image = await TemplatePosters.poster(info.kind, style: .gallery)
                return
            }
            let started = Date()
            while !Task.isCancelled {
                if let frame = await TemplatePosters.image(info.kind, phase: Date().timeIntervalSince(started) / TemplatePosters.period,
                                                           style: .gallery) {
                    image = frame
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
        .help("Makes a new project holding \(info.name), as long as one loop of it.")
    }
}
