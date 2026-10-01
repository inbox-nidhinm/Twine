import SwiftUI
import MotionModel
import Theme

/// What the Info card says about a project: its file's dates and size, and
/// what it holds. Worked out away from the main thread.
struct ProjectDetails: Sendable {
    var created: Date?
    /// Every file in the package, media included.
    var bytes: Int64 = 0
    var composition: Composition?
    var stats: ProjectStats?

    /// `open` is an open project as it stands; otherwise the file is read.
    nonisolated init(url: URL, open: Project?) {
        let project = open ?? (try? Data(contentsOf: url.appendingPathComponent(ProjectFormat.documentFileName)))
            .flatMap { try? ProjectFormat.decode($0) }
        created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        while let file = files?.nextObject() as? URL {
            bytes += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        composition = project?.composition
        stats = project?.stats
    }
}

/// The home screen's Info card on a project, raised from its right-click menu.
struct ProjectInfoCard: View {
    let item: Library.Item
    let library: Library
    let dismiss: () -> Void

    @State private var details: ProjectDetails?
    private let pad: CGFloat = 18

    var body: some View {
        ZStack {
            Theme.badge
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(item.name)
                        .font(ThemeFont.labelStrong)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    IconButton(icon: .close, help: "Close (Esc)", action: dismiss)
                }
                .padding(.leading, pad)
                .padding(.trailing, Theme.sheetCloseInset)
                .frame(height: Theme.sheetHeader)
                .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: Theme.hairline) }

                VStack(alignment: .leading, spacing: Theme.readingSectionGap) {
                    thumbnail
                    if let details { sections(details) }
                }
                .padding(pad)
            }
            .frame(width: Theme.infoCardWidth)
            .floatingPanel()
            .onExitCommand(perform: dismiss)
        }
        .task(id: item.url) { details = await library.details(of: item) }
    }

    @ViewBuilder private var thumbnail: some View {
        if let image = item.thumbnail {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
                .frame(maxWidth: .infinity, maxHeight: Theme.infoThumbnail)
        }
    }

    @ViewBuilder private func sections(_ d: ProjectDetails) -> some View {
        section("File", [
            ("Created", d.created.map(Self.date) ?? "Unknown"),
            ("Last saved", Self.date(item.modified)),
            ("Size", ByteCountFormatter.string(fromByteCount: d.bytes, countStyle: .file)),
        ] + (item.folder.map { [("Folder", $0.lastPathComponent)] } ?? []))
        if let c = d.composition {
            section("Composition", [
                ("Size", "\(c.width) × \(c.height)"),
                ("Length", "\(Self.seconds(c.duration)) · \(c.frameCount) frames"),
                ("Frame rate", "\(c.frameRate.label) fps"),
            ])
        }
        if let s = d.stats {
            section("Layers", [("Total", "\(s.layers)")] + [
                ("Shapes", s.shapes), ("Pictures", s.pictures), ("Text", s.texts), ("Videos", s.videos),
                ("Sounds", s.sounds), ("Groups", s.groups), ("Frames", s.frames),
            ].filter { $0.1 > 0 }.map { ($0.0, "\($0.1)") })
            section("Timeline", [("Actions", "\(s.actions)")] + [
                s.presets > 0 ? ("Presets", "\(s.presets)") : nil,
                s.switchedOff > 0 ? ("Switched off", "\(s.switchedOff)") : nil,
                s.scenes > 0 ? ("Scenes", "\(s.scenes)") : nil,
                s.lastActionEnds.map { ("Last action ends", Self.seconds($0)) },
                s.mediaFiles > 0 ? ("Media files", "\(s.mediaFiles)") : nil,
            ].compactMap { $0 })
        } else {
            Text("This project could not be read.")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func section(_ title: String, _ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, Theme.rowGap)
            ForEach(rows, id: \.0) { row in
                HStack {
                    Text(row.0).foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: Theme.columnGap)
                    Text(row.1).foregroundStyle(Theme.textPrimary).monospacedDigit().lineLimit(1)
                }
                .font(ThemeFont.label)
                .frame(height: Theme.panelRow)
            }
        }
    }

    private static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Up to two places, as many as it needs.
    private static func seconds(_ s: Double) -> String {
        s.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }
}
