import SwiftUI
import AppKit
import AVFoundation
import Theme

/// Whether the onboarding card is up, and where in it: shown on the first
/// launch and never again unless asked for (Help > Show Onboarding). Shared,
/// so the home screen and the editor draw the same card and the test kit can
/// read the page.
@MainActor
@Observable
final class OnboardingState {
    static let shared = OnboardingState()

    var isShowing: Bool
    /// 0 the introduction, 1 the folder, 2 the features.
    var page = 0
    /// The feature the last page is showing. It opens on the first, so there
    /// is always something beside the list.
    var feature = OnboardingFeature.allCases[0]
    /// How many times a folder has been chosen since the card came up. The
    /// folder page's video waits for the first and plays once for each.
    var folderChoices = 0

    private static let seenKey = "hasSeenOnboarding"

    private init() {
        // The test copy opens straight onto its projects; the kit raises the
        // card itself when it wants it.
        let testing = ProcessInfo.processInfo.environment["TWINE_SELFTEST"] != nil
        isShowing = !testing && !UserDefaults.standard.bool(forKey: Self.seenKey)
    }

    func show() {
        page = 0
        feature = OnboardingFeature.allCases[0]
        folderChoices = 0
        isShowing = true
    }

    /// Put away and remembered, however it is left: the last page's button
    /// or Escape on any of them.
    func finish() {
        isShowing = false
        UserDefaults.standard.set(true, forKey: Self.seenKey)
    }
}

/// The five things the last page shows, each with its own artwork.
enum OnboardingFeature: String, CaseIterable, Identifiable {
    case actions, presets, figma, text, export

    var id: String { rawValue }

    var label: String {
        switch self {
        case .actions: "Animate with actions"
        case .presets: "Presets in one click"
        case .figma: "Paste from Figma"
        case .text: "Text letter by letter"
        case .export: "Export up to 4K"
        }
    }

    var title: String {
        switch self {
        case .actions: "Move, scale, fade and more: every action is a bar on the timeline to drag and stretch."
        case .presets: "Bring layers on and off with presets, then tune each one in the inspector."
        case .figma: "Copy frames in Figma with the Twine plugin and paste them in, fills and effects kept."
        case .text: "Animate words a letter, a word or a line at a time."
        case .export: "Export movies with their sound, or stills, at any size up to 4K."
        }
    }

    var icon: Icon {
        switch self {
        case .actions: .move
        case .presets: .presets
        case .figma: .frame
        case .text: .text
        case .export: .export
        }
    }

    /// The artwork's file name in the app's resources (see `OnboardingArt`).
    var art: String { "onboarding-\(rawValue)" }
}

/// The card itself, laid out as Flip's: the app's panel down the left with a
/// sentence, the page's one control and the buttons, artwork filling the
/// right. The pages turn like leaves of a book.
struct OnboardingView: View {
    /// After a new folder is chosen, so the home screen reads it.
    var folderChanged: () -> Void = {}

    private let state = OnboardingState.shared
    @State private var leaf: Double = 0
    @State private var turning = false
    @State private var hovered: OnboardingFeature?
    @State private var folderHover = false
    @State private var folder = Creations.folder
    @State private var keys: Any?

    private let card = Theme.onboardingCard
    private let panelWidth = Theme.onboardingPanel

    var body: some View {
        ZStack {
            // The app's own ground rather than a scrim: on a first launch
            // there is nothing behind worth showing through.
            Theme.canvas
                .grained()
                .contentShape(Rectangle())

            HStack(spacing: 0) {
                panel
                artwork
                    .frame(width: card.width - panelWidth, height: card.height)
            }
            .frame(width: card.width, height: card.height)
            .background(Theme.panel.grained())
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border, lineWidth: Theme.hairline))
            // Hinged on its left edge like a page on a spine, with enough
            // perspective that the far edge foreshortens on the way over.
            .rotation3DEffect(.degrees(leaf), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.35)
            // Lifted while it moves, which puts air under the page.
            .shadow(color: Theme.onboardingShadow.opacity(turning ? 0.65 : 0.5),
                    radius: turning ? 48 : 32, x: turning ? -18 : 0, y: 12)
        }
        .ignoresSafeArea()
        .onAppear(perform: watchKeys)
        .onDisappear(perform: stopWatchingKeys)
    }

    // MARK: The left page

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .displayTitle(Theme.onboardingTitle)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .id(title)

            Spacer(minLength: 20)

            switch state.page {
            case 1: folderRow
            case 2: featureList
            default: EmptyView()
            }

            HStack(spacing: 8) {
                OnboardingButton(label: Self.buttons[state.page], filled: true, action: advance)
                // Only where there is something to go back to.
                if state.page > 0 {
                    OnboardingButton(label: "Back", filled: false, action: retreat)
                }
            }
            .padding(.top, 16)
        }
        .padding(Theme.onboardingPad)
        .frame(width: panelWidth, height: card.height, alignment: .topLeading)
        .background(Theme.panel.grained())
        // Edge-on there is nothing to read, which hides the change of page.
        .opacity(leaf.magnitude > 88 ? 0 : 1)
    }

    /// Where projects go. The path is the button.
    private var folderRow: some View {
        Button(action: chooseFolder) {
            HStack(spacing: 8) {
                IconView(.folder, size: 15)
                    .foregroundStyle(Theme.textTertiary)
                Text(Self.shortPath(folder))
                    .font(ThemeFont.label)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer(minLength: 0)
            }
            .frame(height: Theme.onboardingFolderRow)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Bled out past the text, as the feature rows are, so both pages
            // put their control's left edge where the buttons start.
            .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                .fill(folderHover ? Theme.panelHover : Theme.panelRaised)
                .padding(.horizontal, -8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { folderHover = $0 }
        .help("Choose where Twine keeps your projects")
    }

    /// The five features. Clicking one changes the artwork and the sentence;
    /// going straight for the button is a fine way through too.
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(OnboardingFeature.allCases) { item in
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { state.feature = item }
                } label: {
                    HStack(spacing: 8) {
                        IconView(item.icon, size: 15)
                        Text(item.label)
                            .font(ThemeFont.label)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(item == state.feature ? Theme.textPrimary : Theme.textSecondary)
                    .frame(height: Theme.onboardingRow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .fill(item == state.feature ? Theme.rowSelected : hovered == item ? Theme.rowHover : .clear)
                        .padding(.horizontal, -8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // Guarded, since moving down the list delivers the next row's
                // true before the last row's false.
                .onHover { inside in
                    if inside { hovered = item } else if hovered == item { hovered = nil }
                }
            }
        }
    }

    // MARK: The right page

    @ViewBuilder private var artwork: some View {
        ZStack {
            switch state.page {
            case 0: OnboardingArt(name: "onboarding-intro")
            // The folder's name is whichever was chosen, so the app writes it.
            // Its video fills the folder, so it plays when one is chosen.
            case 1: OnboardingArt(name: "onboarding-folder", caption: folder.lastPathComponent,
                                  plays: state.folderChoices)
            default:
                OnboardingArt(name: state.feature.art)
                    .id(state.feature)
                    .transition(.opacity)
            }
        }
        .clipped()
        .opacity(leaf.magnitude > 88 ? 0 : 1)
    }

    // MARK: Turning the page

    private func advance() {
        guard !turning else { return }
        guard state.page + 1 < Self.buttons.count else { return state.finish() }
        turn(to: state.page + 1, forwards: true)
    }

    private func retreat() {
        guard !turning, state.page > 0 else { return }
        turn(to: state.page - 1, forwards: false)
    }

    /// The leaf lifts to edge-on, the page changes where nothing shows, and
    /// it comes down from the other side. One hinge in two halves, since the
    /// card has content on one face only.
    private func turn(to next: Int, forwards: Bool) {
        turning = true
        let away: Double = forwards ? 90 : -90
        withAnimation(.easeIn(duration: 0.22)) { leaf = away }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            state.page = next
            // Set without animating, so it arrives from the far side.
            leaf = -away
            withAnimation(.easeOut(duration: 0.26)) { leaf = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { turning = false }
        }
    }

    private func chooseFolder() {
        Creations.chooseFolder(for: MainWindow.window) { chosen in
            guard chosen else { return }
            folder = Creations.folder
            state.folderChoices += 1
            folderChanged()
        }
    }

    // MARK: Keys

    /// While the card is up it has the keyboard: Escape leaves, Return turns
    /// the page, and nothing reaches the canvas, the timeline or a field
    /// behind it. Command keys still reach the menus, so Quit works.
    private func watchKeys() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.command) { return event }
            switch event.keyCode {
            case 53: state.finish()
            case 36, 76: advance()
            default: break
            }
            return nil
        }
    }

    private func stopWatchingKeys() {
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    // MARK: The words

    private var title: String {
        state.page == Self.buttons.count - 1 ? state.feature.title : Self.titles[state.page]
    }

    private static let titles = [
        "Twine, a motion design tool where layers move by actions, not keyframes.",
        "Choose a folder to keep your projects in. Twine saves them as you work.",
    ]

    private static let buttons = ["Get started", "Continue", "Start animating"]

    /// `~/Documents/Twine Creations` rather than the whole way from the root.
    private static func shortPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

// MARK: - Artwork

/// One page's artwork, filling its side of the card: a looping video named
/// `name` (.mp4 or .mov) in the app's resources, else a picture (.png or
/// .jpg), else a placeholder. Dropping the files into `Twine/Resources` is
/// all it takes to replace a placeholder.
private struct OnboardingArt: View {
    let name: String
    /// Written under the folder in the artwork: the chosen folder's name.
    var caption: String?
    /// Nil loops the video. A count plays it once each time it goes up,
    /// holding the first frame until then and the last after.
    var plays: Int?

    var body: some View {
        ZStack {
            if let url = Self.file(name, ["mp4", "mov"]) {
                LoopingVideo(url: url, plays: plays)
            } else if let image = Self.image(name) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Theme.panelRaised.grained()
                IconView(.image, size: 40)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .overlay {
            if let caption {
                GeometryReader { space in
                    FolderName(text: caption, in: space.size)
                }
            }
        }
    }

    /// The name set where the designer put it, under the folder: the
    /// artwork fills its box as the video does, cut evenly off two sides,
    /// and the type is placed and sized in the artwork's own pixels, scaled
    /// with it.
    private struct FolderName: View {
        let text: String
        let box: CGSize

        init(text: String, in box: CGSize) {
            self.text = text
            self.box = box
        }

        var body: some View {
            let art = Theme.onboardingArtwork
            let scale = max(box.width / art.width, box.height / art.height)
            let top = (box.height - art.height * scale) / 2
            let baseline = top + Theme.onboardingFolderBaseline * scale
            Text(text)
                .font(.system(size: Theme.onboardingFolderName * scale))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, Theme.onboardingPad)
                .frame(width: box.width)
                // The baseline, not the box, goes to its place.
                .alignmentGuide(.top) { $0[.lastTextBaseline] - baseline }
                .frame(width: box.width, height: box.height, alignment: .top)
        }
    }

    private static func file(_ name: String, _ extensions: [String]) -> URL? {
        extensions.lazy.compactMap { Bundle.main.url(forResource: name, withExtension: $0) }.first
    }

    /// Held for the session, so turning back does not decode it again.
    @MainActor private static var images: [String: NSImage] = [:]

    @MainActor private static func image(_ name: String) -> NSImage? {
        if let hit = images[name] { return hit }
        guard let url = file(name, ["png", "jpg"]), let image = NSImage(contentsOf: url) else { return nil }
        images[name] = image
        return image
    }
}

/// A silent video filling its box, playing round and round, or with `plays`
/// once each time the count goes up.
private struct LoopingVideo: NSViewRepresentable {
    let url: URL
    var plays: Int?

    func makeNSView(context: Context) -> VideoView { VideoView() }

    func updateNSView(_ view: VideoView, context: Context) {
        if let plays { view.play(url, times: plays) } else { view.play(url) }
    }

    static func dismantleNSView(_ view: VideoView, coordinator: ()) { view.stop() }

    final class VideoView: NSView {
        private let player = AVQueuePlayer()
        private let playerLayer = AVPlayerLayer()
        private var looper: AVPlayerLooper?
        private var url: URL?
        /// The plays already started, for a video that plays once.
        private var played: Int?

        init() {
            super.init(frame: .zero)
            wantsLayer = true
            player.isMuted = true
            playerLayer.player = player
            playerLayer.videoGravity = .resizeAspectFill
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("not built from a nib") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        func play(_ url: URL) {
            guard url != self.url else { return }
            self.url = url
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            player.play()
        }

        /// Once from the start whenever `times` goes up. Made with plays
        /// already counted (the page turned back to), it rests on the last
        /// frame; with none, on the first.
        func play(_ url: URL, times: Int) {
            if url != self.url {
                self.url = url
                looper = nil
                // Kept at the end rather than taken off the queue, so the
                // last frame stays.
                player.actionAtItemEnd = .pause
                let item = AVPlayerItem(url: url)
                player.removeAllItems()
                player.insert(item, after: nil)
                played = times
                if times > 0 { rest(atEndOf: item) }
                return
            }
            guard let played, times > played else { return }
            self.played = times
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [player] _ in
                player.play()
            }
        }

        private func rest(atEndOf item: AVPlayerItem) {
            Task { @MainActor [player] in
                guard let length = try? await item.asset.load(.duration) else { return }
                let last = CMTimeSubtract(length, CMTime(value: 1, timescale: 120))
                await player.seek(to: last, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }

        func stop() {
            player.pause()
            looper = nil
        }
    }
}

/// One of the pair at the foot of a page: the one that moves on is the
/// accent, the one that goes back a step up from the panel.
private struct OnboardingButton: View {
    let label: String
    let filled: Bool
    let action: () -> Void

    @State private var hovering = false

    private var fill: Color {
        if filled { return hovering ? Theme.accentHover : Theme.accent }
        return hovering ? Theme.panelHover : Theme.panelRaised
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(ThemeFont.labelStrong)
                .foregroundStyle(filled ? Theme.textOnColor : Theme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: Theme.onboardingButton)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl).fill(fill))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
