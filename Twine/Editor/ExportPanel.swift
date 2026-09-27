import SwiftUI
import AppKit
import QuartzCore
import MotionModel
import MotionEvaluation
import MotionRendering
import MotionExport
import Theme

/// Export, as a panel over the whole window: the settings down the left, and
/// on the right a preview of exactly what will be written, which plays at
/// the export's frame rate with its sound. Exporting sends the player up and
/// out and brings a counter up from below, its digits stepping up as the
/// frames are written; when it ends they trade places back, and the button
/// offers to export again. Closing the panel (the cross, or Escape) stops an
/// export in flight.
struct ExportPanel: View {
    let title: String
    @Bindable var session: ExportSession
    let controller: EditorController
    @Bindable var editor: EditorModel
    /// Whether anything in the project makes a sound.
    let hasSound: Bool

    @State private var player: ExportPreviewPlayer?
    /// The counter's number, kept after an export ends so it leaves showing
    /// where it got to.
    @State private var percent = 0
    /// Follows the export, but lets go a moment after it ends, so the last
    /// digits finish stepping before the counter leaves.
    @State private var showsCounter = false
    /// Whether the size is typed as a percentage rather than picked.
    @State private var typesSize = false

    private var settings: ExportSettings { session.settings }
    private var composition: Composition { controller.project.composition }
    private var isMovie: Bool { settings.format.isMovie }

    var body: some View {
        HStack(spacing: 0) {
            settingsColumn
                .frame(width: Theme.exportColumn)
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
            stage
        }
        .overlay(alignment: .topTrailing) {
            IconButton(icon: .close, help: session.isExporting ? "Stop the export and close (Esc)" : "Close (Esc)") {
                controller.closeExport()
            }
            .padding(Theme.panelPad - 4)
        }
        .floatingPanel()
        .padding(Theme.floatInset)
        .background(Theme.canvas.grained().ignoresSafeArea())
        // Clicks never reach the canvas underneath.
        .contentShape(Rectangle())
        .onAppear(perform: setUp)
        .onDisappear {
            player?.pause()
            editor.exportPlayer = nil
        }
        .onChange(of: session.progress) { _, progress in
            if let progress { percent = Int((progress * 100).rounded(.down)) }
        }
        .onChange(of: session.isExporting) { _, exporting in
            if exporting {
                percent = 0
                showsCounter = true
            } else {
                percent = Int((session.lastProgress * 100).rounded(.down))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if !session.isExporting { showsCounter = false }
                }
            }
        }
        .onChange(of: session.settings) { _, _ in fitPlayer() }
        .onChange(of: session.range) { _, _ in fitPlayer() }
    }

    // MARK: Settings

    private var settingsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(ThemeFont.display(Theme.exportTitle))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .padding(.horizontal, Theme.panelPad)
                // Clear of the window's close, minimise and zoom buttons, as
                // the layers panel's name is.
                .padding(.top, 44)
            Spacer(minLength: Theme.panelPad)
            Group {
                PanelDivider()
                formatSection
                if isMovie {
                    PanelDivider()
                    rangeSection
                }
                if hasSound && isMovie {
                    PanelDivider()
                    ToggleRow(label: "Audio", isOn: settings.includesAudio) { session.settings.includesAudio.toggle() }
                        .help("Includes the sound of the project's video and audio layers.")
                        .padding(Theme.panelPad)
                }
            }
            .disabled(session.isExporting)
            .opacity(session.isExporting ? 0.5 : 1)
            PanelDivider()
            actions
        }
    }

    private var formatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Export format")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            MenuField(value: sizeTitle, entries: sizeEntries)
            if typesSize {
                UnitField(unit: "Scale", value: shownPercent, decimals: 1, suffix: "%",
                          accepts: { $0 >= ExportSettings.minScale * 100 && $0 <= largestPercent + 1e-9 }) { v in
                    session.settings.scale = v / 100
                }
                .help("Any size, as a share of the composition's, up to 4K (3840 × 2160 either way round). "
                      + "Movies round to even numbers of pixels.")
            }
            HStack(spacing: 8) {
                MenuField(value: settings.format.shortTitle, entries: formatEntries)
                    .help("H.264, HEVC and ProRes 422 have no transparency, so a transparent background "
                          + "exports as its colour. HEVC with alpha, ProRes 4444 and PNG keep it. "
                          + "A PNG is the frame under the playhead, or in Design, the layout as designed.")
                if isMovie {
                    MenuField(value: "\(exportRate.label) fps", entries: rateEntries)
                        .help("The movie's frame rate. The scene is the same; a lower rate shows it less often.")
                }
            }
        }
        .padding(Theme.panelPad)
    }

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuRow(label: "Range", value: session.range == nil ? "Whole scene" : "Part of the scene", entries: rangeEntries)
            if let range = session.range {
                HStack(spacing: 8) {
                    UnitField(unit: "From", value: range.lowerBound, decimals: 2, suffix: "s",
                              accepts: { $0 >= 0 && $0 < range.upperBound }) { v in
                        session.range = snapped(v)...range.upperBound
                    }
                    UnitField(unit: "To", value: range.upperBound, decimals: 2, suffix: "s",
                              accepts: { $0 > range.lowerBound }) { v in
                        session.range = range.lowerBound...min(snapped(v), composition.duration)
                    }
                }
                .help("The part of the scene to export, in seconds. The movie starts at From.")
            }
        }
        .padding(Theme.panelPad)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: session.isExporting ? "Cancel" : session.completed != nil ? "Export again" : "Export") {
                if session.isExporting {
                    session.cancel()
                } else {
                    player?.pause()
                    session.request(nil)
                }
            }
            .help(session.isExporting ? "Stop the export" : "Choose where to save it. (⌘E)")
            if let url = session.completed, !session.isExporting {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Text("Show in Finder")
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.panelRow)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(url.lastPathComponent)
            }
        }
        .padding(Theme.panelPad)
    }

    // MARK: The preview and the counter

    private var stage: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack {
                player.map { player in
                    PreviewPlayerView(player: player, controller: controller, editor: editor, settings: settings,
                                      isMovie: isMovie)
                        .padding(.horizontal, proxy.size.width * 0.14)
                        .padding(.vertical, height * 0.12)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .offset(y: showsCounter ? -height : 0)

                StepCounter(value: percent, size: height * Theme.exportCounterShare)
                    .padding(.trailing, Theme.panelPad * 4)
                    .padding(.bottom, Theme.panelPad * 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(y: showsCounter ? 0 : height)
            }
            .animation(Theme.exportEase, value: showsCounter)
        }
        .clipped()
    }

    // MARK: Setting up

    private func setUp() {
        let made = ExportPreviewPlayer(project: { [weak controller] in controller?.project ?? Project() },
                                       locate: { [weak controller] id in controller?.document?.mediaURL(for: id) })
        player = made
        editor.exportPlayer = made
        typesSize = !ExportSettings.scales.contains(settings.scale)
        fitPlayer()
        if session.isExporting {
            percent = Int(((session.progress ?? 0) * 100).rounded(.down))
            showsCounter = true
        }
    }

    /// The player plays what will be exported: the range, at the export's rate.
    private func fitPlayer() {
        guard let player else { return }
        player.rate = exportRate
        player.span = session.range ?? 0...composition.duration
        player.seek(player.time)
    }

    private var exportRate: FrameRate { settings.frameRate ?? composition.frameRate }

    // MARK: Menus

    private var sizeTitle: String {
        let (width, height) = settings.pixelSize(of: composition)
        return "\(width) × \(height) px"
    }

    /// A size too big for 4K is offered greyed out, at the size it would be.
    private func sizeEntries() -> [MenuEntry] {
        let presets = ExportSettings.scales.map { scale -> MenuEntry in
            let fits = scale <= ExportSettings.largestScale(for: composition) + 1e-9
            var s = settings
            s.scale = scale
            let (w, h) = fits ? s.pixelSize(of: composition)
                : (Int((Double(composition.width) * scale).rounded()), Int((Double(composition.height) * scale).rounded()))
            return MenuEntry.item("\(Int(scale * 100))%   \(w) × \(h)",
                                  checked: !typesSize && abs(scale - settings.effectiveScale(for: composition)) < 1e-9,
                                  disabled: !fits) {
                session.settings.scale = scale
                typesSize = false
            }
        }
        return presets + [.separator, .item("Custom…", checked: typesSize) { typesSize = true }]
    }

    private var shownPercent: Double { (settings.effectiveScale(for: composition) * 1000).rounded() / 10 }
    private var largestPercent: Double { ExportSettings.largestScale(for: composition) * 100 }

    private func formatEntries() -> [MenuEntry] {
        let groups: [[ExportFormat]] = [[.h264, .hevc], [.hevcAlpha, .proRes422, .proRes4444], [.png]]
        return groups.enumerated().flatMap { index, formats in
            (index > 0 ? [MenuEntry.separator] : []) + formats.map { format in
                MenuEntry.item(format.title, checked: format == settings.format) { session.settings.format = format }
            }
        }
    }

    /// The composition's own rate first, then the usual ones.
    private func rateEntries() -> [MenuEntry] {
        let own = composition.frameRate
        let others = ExportSettings.frameRates.filter { $0 != own }
        return [.item("\(own.label) fps   Composition", checked: settings.frameRate == nil || settings.frameRate == own) {
            session.settings.frameRate = nil
        }, .separator] + others.map { rate in
            .item("\(rate.label) fps", checked: settings.frameRate == rate) { session.settings.frameRate = rate }
        }
    }

    private func rangeEntries() -> [MenuEntry] {
        [
            .item("Whole scene", checked: session.range == nil) { session.range = nil },
            .item("Part of the scene", checked: session.range != nil) {
                if session.range == nil { session.range = 0...composition.duration }
            },
        ]
    }

    private func snapped(_ seconds: Double) -> Double { composition.frameRate.snapped(max(seconds, 0)) }
}

/// The keyboard while the export panel is up: Escape closes it, Space plays
/// the preview, and nothing reaches the layers or the timeline behind it.
enum ExportKeys {
    static func handle(_ event: NSEvent, _ controller: EditorController) -> Bool {
        guard controller.editor.showExport else { return false }
        switch event.keyCode {
        case 53: controller.closeExport()
        case 49 where !event.isARepeat: controller.editor.exportPlayer?.toggle()
        default: break
        }
        return true
    }
}

// MARK: - Player

/// The preview's own playhead, apart from the editor's: it plays the export's
/// range at the export's frame rate, with the sound, and stops at the end.
@MainActor
@Observable
final class ExportPreviewPlayer {
    /// Seconds into the composition.
    var time: Double = 0
    private(set) var isPlaying = false
    /// What the export holds.
    var span: ClosedRange<Double> = 0...1
    var rate: FrameRate = .fps60

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTick: CFTimeInterval?
    @ObservationIgnored private let ticker = Ticker()
    @ObservationIgnored private let audio: AudioPreview
    @ObservationIgnored private let project: () -> Project

    init(project: @escaping () -> Project, locate: @escaping (UUID) -> URL?) {
        self.project = project
        audio = AudioPreview(locate: locate)
        ticker.tick = { [weak self] link in self?.tick(link) }
    }

    /// The moment on screen: the start of the export frame the playhead is in.
    var shownTime: Double { rate.time(ofFrame: rate.frame(at: time)) }

    /// How far through the span, from 0 to 1.
    var fraction: Double {
        let length = span.upperBound - span.lowerBound
        return length > 0 ? min(max((time - span.lowerBound) / length, 0), 1) : 0
    }

    func toggle() { isPlaying ? pause() : play() }

    func play() {
        guard !isPlaying else { return }
        // At the end, playing starts again from the beginning.
        if time >= span.upperBound - rate.frameDuration { time = span.lowerBound }
        isPlaying = true
        lastTick = nil
        let link = NSScreen.main?.displayLink(target: ticker, selector: #selector(Ticker.fire(_:)))
        link?.add(to: .main, forMode: .common)
        self.link = link
        audio.follow(project(), time: time, playing: true)
    }

    func pause() {
        link?.invalidate()
        link = nil
        guard isPlaying else { return }
        isPlaying = false
        audio.follow(project(), time: time, playing: false)
    }

    func seek(_ seconds: Double) {
        time = min(max(seconds, span.lowerBound), span.upperBound)
        if isPlaying { audio.follow(project(), time: time, playing: true) }
    }

    private func tick(_ link: CADisplayLink) {
        defer { lastTick = link.targetTimestamp }
        guard let last = lastTick else { return }
        time += link.targetTimestamp - last
        if time >= span.upperBound {
            time = span.upperBound
            pause()
            return
        }
        audio.follow(project(), time: time, playing: true)
    }

    /// A display link needs an Objective-C target; this one hands each tick on.
    private final class Ticker: NSObject {
        var tick: (CADisplayLink) -> Void = { _ in }
        @objc func fire(_ link: CADisplayLink) { tick(link) }
    }
}

/// The preview and, for a movie, its play button, progress and time.
private struct PreviewPlayerView: View {
    let player: ExportPreviewPlayer
    let controller: EditorController
    let editor: EditorModel
    let settings: ExportSettings
    let isMovie: Bool

    var body: some View {
        let c = controller.project.composition
        VStack(spacing: Theme.previewGap) {
            ExportPreview(controller: controller, time: isMovie ? player.shownTime : editor.time,
                          design: !isMovie && editor.mode == .design, keepsTransparency: settings.format.keepsTransparency)
                .aspectRatio(CGFloat(max(c.width, 1)) / CGFloat(max(c.height, 1)), contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
            if isMovie {
                PreviewControls(player: player)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PreviewControls: View {
    let player: ExportPreviewPlayer

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.panelPad * 2) {
            Button { player.toggle() } label: {
                IconView(player.isPlaying ? .pause : .play, size: Theme.icon)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: Theme.previewButton, height: Theme.previewButton)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                        .fill(hovering ? Theme.panelHover : Theme.panelRaised))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(player.isPlaying ? "Pause (Space)" : "Play (Space)")

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.panelRaised)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(Theme.progressBar, proxy.size.width * player.fraction))
                }
                .frame(height: Theme.progressBar)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(max(g.location.x / max(proxy.size.width, 1), 0), 1)
                    player.seek(player.span.lowerBound + f * (player.span.upperBound - player.span.lowerBound))
                })
            }
            .frame(height: Theme.previewButton)

            Text(clock(player.time))
                .font(ThemeFont.title)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }

    /// Minutes and seconds, as a player reads them.
    private func clock(_ seconds: Double) -> String {
        let whole = Int(max(seconds, 0).rounded(.down))
        return String(format: "%02d:%02d", whole / 60, whole % 60)
    }
}

// MARK: - The picture

/// The scene drawn as the export will draw it: fitted to the space, over
/// the background colour, or a checkerboard where the format keeps
/// transparency and the background is transparent.
private struct ExportPreview: NSViewRepresentable {
    let controller: EditorController
    let time: Double
    let design: Bool
    let keepsTransparency: Bool

    func makeNSView(context: Context) -> ExportPreviewView {
        let view = ExportPreviewView()
        view.media = controller.media
        return view
    }

    func updateNSView(_ view: ExportPreviewView, context: Context) {
        var project = controller.project
        if !keepsTransparency { project.composition.background.isTransparent = false }
        view.show(design ? evaluateDesign(project) : evaluate(project, at: time))
    }
}

final class ExportPreviewView: NSView {
    private let renderer = CoreAnimationRenderer()
    private let world = CALayer()
    private let backdrop = CALayer()
    private var size = Size2(1, 1)

    var media: MediaProvider? {
        didSet { renderer.media = media }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        layer?.masksToBounds = true
        for l in [world, backdrop] {
            l.anchorPoint = .zero
            l.actions = ["transform": NSNull(), "position": NSNull(), "bounds": NSNull(), "backgroundColor": NSNull()]
        }
        world.addSublayer(renderer.rootLayer)
        layer?.addSublayer(backdrop)
        layer?.addSublayer(world)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not built from a nib") }

    override var isFlipped: Bool { true }

    func show(_ scene: ResolvedScene) {
        size = scene.size
        backdrop.backgroundColor = scene.background?.cgColor ?? CanvasNSView.checkerColor
        renderer.render(scene)
        place()
    }

    override func layout() {
        super.layout()
        place()
    }

    /// The composition fitted into the view, which already has its shape.
    private func place() {
        guard size.width > 0, size.height > 0, bounds.width > 0 else { return }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let wanted = (window?.backingScaleFactor ?? 2) * max(scale, 0.25)
        if abs(renderer.contentsScale - wanted) > 0.01 { renderer.contentsScale = wanted }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        world.transform = CATransform3DMakeScale(scale, scale, 1)
        backdrop.frame = bounds
        CATransaction.commit()
    }
}

// MARK: - The counter

/// The export's progress as a big number and a percent sign. Each digit
/// that changes steps up once: the old one rises out of its window as the
/// new one rises in from below, however far the number jumped, so fast
/// progress reads as calm steps rather than spinning digits. A new place
/// (10, 100) rises in from below too.
private struct StepCounter: View {
    let value: Int
    let size: CGFloat

    var body: some View {
        let places = value >= 100 ? [2, 1, 0] : value >= 10 ? [1, 0] : [0]
        HStack(alignment: .center, spacing: 0) {
            ForEach(places, id: \.self) { place in
                DigitStep(digit: value / Int(pow(10, Double(place))) % 10, size: size)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Text("%")
                .font(ThemeFont.display(size))
                .foregroundStyle(Theme.textPrimary)
                .offset(y: ThemeFont.displayFigures(size).nudge)
                .frame(height: DigitStep.window(size))
        }
        .animation(Theme.counterEase, value: places.count)
        .fixedSize()
    }
}

/// One place of the counter: its digit, which steps up to the next when it
/// changes, the two fading at the window's top and bottom edges.
private struct DigitStep: View {
    let digit: Int
    let size: CGFloat

    /// Each digit's window: the figures' height with room above and below,
    /// where stepping digits fade in and out.
    static func window(_ size: CGFloat) -> CGFloat { ThemeFont.displayFigures(size).height * Theme.counterWindow }

    /// Opaque in the middle, fading to nothing at the top and bottom edges.
    /// (A mask only reads its colours' opacity.)
    private static let feather = LinearGradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: Theme.counterFeather),
        .init(color: .black, location: 1 - Theme.counterFeather),
        .init(color: .clear, location: 1),
    ], startPoint: .top, endPoint: .bottom)

    var body: some View {
        let height = Self.window(size)
        ZStack {
            Text("\(digit)")
                .font(ThemeFont.display(size))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
                .offset(y: ThemeFont.displayFigures(size).nudge)
                .id(digit)
                .transition(.asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top)))
        }
        .frame(width: ThemeFont.displayDigitWidth(size), height: height)
        .animation(Theme.counterEase, value: digit)
        .clipped()
        .mask(Self.feather)
    }
}
