import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionRendering
import CoreImage
import Theme

/// The two ways to start animating the selection, as big tiles: a new action
/// from the menu, or a preset from the picker.
struct ActionTiles: View {
    let newActions: [MenuEntry]
    let hasPresets: Bool
    let pickPreset: () -> Void

    @Environment(MenuHost.self) private var menus
    @State private var newFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 8) {
            BigTile(icon: .plus, title: "New Action", disabled: newActions.isEmpty) {
                menus.show(newActions, at: CGPoint(x: newFrame.minX, y: newFrame.maxY + 4))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { newFrame = $0 }
            .help("Adds an action at the playhead, half a second long.")
            BigTile(icon: .presets, title: "Select Preset", disabled: !hasPresets, action: pickPreset)
                .help("Picks a ready-made animation to add at the playhead, as one bar you can adjust.")
        }
    }
}

/// A square button with an icon over its name.
private struct BigTile: View {
    let icon: Icon
    let title: String
    var disabled = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    VStack(spacing: 8) {
                        IconView(icon, size: Theme.icon + 4)
                        Text(title)
                            .font(ThemeFont.label)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(disabled ? Theme.textTertiary : Theme.textPrimary)
                }
                .background(RoundedRectangle(cornerRadius: Theme.radiusWell)
                    .fill(hovering && !disabled ? Theme.panelHover : Theme.panelRaised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}

/// Every preset the selection can take, in headed groups, each on a tile
/// that plays it, so what you pick is what you saw. A pair (Fade In and
/// Fade Out) is one tile playing both; it goes on as In and turns to Out in
/// its settings.
struct PresetPicker: View {
    let presets: [Preset]
    /// Picking puts the preset in the selected bars' place rather than adding it.
    var swapping = false
    let pick: (Preset) -> Void
    let close: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    @State private var search = ""
    @FocusState private var searching: Bool

    /// The presets whose name, other way's name (Fade Out for Fade) or group
    /// holds what is typed, every one while nothing is.
    private var matching: [Preset] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return presets }
        return presets.filter { preset in
            [preset.name, Presets.name(of: preset.kind), preset.kind.reversed.map(Presets.name(of:)) ?? "", preset.group.title]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// With text selected, the Text group comes first.
    private var groups: [PresetGroup] {
        guard presets.contains(where: \.isText) else { return PresetGroup.allCases }
        return [.text] + PresetGroup.allCases.filter { $0 != .text }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(title: "Presets") {
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
                    // Return takes the first match, as the first tile shown.
                    .onSubmit { if let first = groups.lazy.compactMap({ g in matching.first { $0.group == g } }).first { pick(first) } }
                    .onAppear { searching = true }
                if matching.isEmpty {
                    Text("No presets")
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textTertiary)
                }
                ForEach(groups, id: \.self) { group in
                    let shown = matching.filter { $0.group == group }
                    if !shown.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(ThemeFont.labelStrong)
                                .foregroundStyle(Theme.textPrimary)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(shown) { preset in
                                    PresetTile(preset: preset, swapping: swapping) { pick(preset) }
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

private struct PresetTile: View {
    let preset: Preset
    var swapping = false
    let pick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { PresetThumbnail(preset: preset) }
                    .background(hovering ? Theme.panelHover : Theme.panelRaised)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusWell))
                Text(preset.name)
                    .font(ThemeFont.caption)
                    .foregroundStyle(hovering ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(swapping ? "Puts \(preset.name) in the selected preset's place"
              : preset.isText ? "Adds \(preset.name) at the playhead, moving the text \(preset.text?.unit?.rawValue ?? "letters") one by one"
              : preset.kind.reversed == nil ? "Adds \(preset.name) at the playhead"
              : "Adds \(Presets.name(of: preset.kind)) at the playhead; its settings turn it to \(preset.name) Out")
    }
}

/// A preset playing on a stand-in, over and over. The motion is the real
/// one, worked out by the same rules that play it on the canvas, so the
/// tile can never show something the preset does not do. A text preset
/// plays on a row of small squares standing for its letters.
struct PresetThumbnail: View {
    let preset: Preset

    var body: some View {
        let preview = PresetPreview.of(preset)
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: preview.period)
            let state = preview.state(at: t)
            let letters = preview.letters(at: t)
            Canvas { context, size in
                if preview.isSound {
                    Self.drawSound(state, in: &context, size: size)
                } else if let letters {
                    let k = size.width / PresetPreview.scene
                    for (i, letter) in letters.enumerated() {
                        var c = context
                        c.translateBy(x: PresetPreview.letterCentre(i) * k, y: PresetPreview.scene / 2 * k)
                        Self.drawShape(letter, side: PresetPreview.letter, in: &c, scale: k)
                    }
                } else {
                    var c = context
                    let k = size.width / PresetPreview.scene
                    c.translateBy(x: state.position.x * k, y: state.position.y * k)
                    Self.drawShape(state, side: PresetPreview.side, in: &c, scale: k)
                }
            }
        }
    }

    /// A rounded square of `side` at the context's origin, as `state` has
    /// it: faded, blurred, turned, scaled, tilted (drawn as the narrowing a
    /// turn in depth gives) and clipped by any reveal.
    private static func drawShape(_ state: LayerState, side: Double, in context: inout GraphicsContext, scale k: Double) {
        guard state.isShown, state.opacity > 0.001, !state.reveal.showsNothing,
              abs(state.scale.x) > 0.0001, abs(state.scale.y) > 0.0001 else { return }
        context.opacity = state.opacity
        // Blur is stored as Figma has it, twice the spread.
        if state.layerBlur > 0 { context.addFilter(.blur(radius: state.layerBlur / 2 * k)) }
        // A page curl is Core Image's, as on the canvas, on a picture of the square.
        if case .curled(let curl) = state.curl {
            let w = side * k
            guard let picture = PresetPreview.curled(curl, side: w) else { return }
            context.draw(Image(decorative: picture, scale: PresetPreview.curlScale),
                         in: CGRect(x: -w / 2, y: -w / 2, width: w, height: w))
            return
        }
        // A turn in depth is drawn in its true perspective, about its hinge
        // when it has one, so a page turn swings on its edge.
        if state.tilt.isTilted {
            let turn = Projective.layer(position: .zero, anchor: Vec2(side / 2, side / 2), scale: state.scale,
                                        rotation: state.rotation, skew: state.skew, tilt: state.tilt,
                                        size: Size2(side, side))
            let flat = RoundedRectangle(cornerRadius: side * PresetPreview.roundness)
                .path(in: CGRect(x: 0, y: 0, width: side, height: side))
            context.fill(projected(flat, turn, scale: k), with: .color(Theme.previewShape))
            return
        }
        context.rotate(by: .degrees(state.rotation))
        context.scaleBy(x: state.scale.x * max(abs(cos(state.tilt.y * .pi / 180)), 0.001),
                        y: state.scale.y * max(abs(cos(state.tilt.x * .pi / 180)), 0.001))
        let w = side * k, h = side * k
        let box = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        if case .clipped(let r) = state.reveal {
            context.clip(to: Path(CGRect(x: box.minX + r.x * w, y: box.minY + r.y * h, width: r.width * w, height: r.height * h)))
            context.translateBy(x: r.dx * w, y: r.dy * h)
            context.scaleBy(x: r.zoom, y: r.zoom)
        }
        context.fill(RoundedRectangle(cornerRadius: w * PresetPreview.roundness).path(in: box),
                     with: .color(Theme.previewShape))
    }

    /// `path` carried point by point through `turn`, then scaled to the tile.
    private static func projected(_ path: Path, _ turn: Projective, scale k: Double) -> Path {
        func place(_ q: CGPoint) -> CGPoint {
            let v = turn.apply(Vec2(q.x, q.y)) ?? .zero
            return CGPoint(x: v.x * k, y: v.y * k)
        }
        var out = Path()
        path.forEach { element in
            switch element {
            case .move(let to): out.move(to: place(to))
            case .line(let to): out.addLine(to: place(to))
            case .quadCurve(let to, let control): out.addQuadCurve(to: place(to), control: place(control))
            case .curve(let to, let c1, let c2): out.addCurve(to: place(to), control1: place(c1), control2: place(c2))
            case .closeSubpath: out.closeSubpath()
            }
        }
        return out
    }

    /// A sound has nothing to draw, so its level is shown as bars.
    private static func drawSound(_ state: LayerState, in context: inout GraphicsContext, size: CGSize) {
        let level = min(max(state.volume ?? 1, 0), 1)
        let heights: [CGFloat] = [0.35, 0.65, 1, 0.65, 0.35]
        let bar = size.width * 0.07, gap = bar * 0.8, tallest = size.height * 0.5
        let total = CGFloat(heights.count) * bar + CGFloat(heights.count - 1) * gap
        for (i, f) in heights.enumerated() {
            let h = max(tallest * f * level, bar)
            let box = CGRect(x: (size.width - total) / 2 + CGFloat(i) * (bar + gap), y: (size.height - h) / 2,
                             width: bar, height: h)
            context.fill(Capsule().path(in: box), with: .color(Theme.previewShape))
        }
    }
}

/// A preset on a stand-in layer in a small square scene, worked out once per
/// preset and kept.
@MainActor
struct PresetPreview {
    /// The side of the scene a tile shows, in the scene's pixels. The preset
    /// travels its real distances in it, so a slide and a shake keep their
    /// sizes against each other.
    static let scene = 320.0
    /// The stand-in: a rounded square, so a turn shows as a circle's would not.
    static let side = 128.0
    static let roundness = 0.22
    /// A text preset's letters: five small squares in a row.
    static let letter = 44.0
    static let letters = 5
    private static let letterGap = 12.0
    /// An empty moment before it plays, a hold between a pair's In and Out,
    /// and a rest after, so each loop reads as one go.
    private static let lead = 0.35
    private static let hold = 0.5
    private static let rest = 0.7

    let layer: Layer
    let tracks: ActionTracks
    let period: Double
    let isSound: Bool
    let isText: Bool

    private static var cache: [String: PresetPreview] = [:]

    static func of(_ preset: Preset) -> PresetPreview {
        if let known = cache[preset.id] { return known }
        let made = make(preset)
        cache[preset.id] = made
        return made
    }

    /// The centre of letter `i` across the scene.
    static func letterCentre(_ i: Int) -> Double {
        let total = Double(letters) * letter + Double(letters - 1) * letterGap
        return (scene - total) / 2 + letter / 2 + Double(i) * (letter + letterGap)
    }

    private static func make(_ preset: Preset) -> PresetPreview {
        let isSound = preset.isSound
        let corner = Vec2((scene - side) / 2, (scene - side) / 2)
        let layer = isSound
            ? Layer(name: preset.name, content: .audio(AudioContent(mediaID: UUID())),
                    size: Size2(side, side), position: Vec2(scene / 2, scene / 2))
            : LayerFactory.shape(.rectangle, in: Box(origin: corner, size: Size2(side, side)), name: preset.name)
        let rate = FrameRate(frames: 60)
        var first = Presets.action(preset, for: layer, at: lead, frameRate: rate)
        // Letters travel their own size, as they do on a text.
        if preset.isText, case .preset(var p) = first.spec, p.distance != nil {
            p.distance = letter
            first.spec = .preset(p)
        }
        var actions = [first]
        // A pair plays its way in, then its way out, with the same settings.
        if let out = preset.kind.reversed, case .preset(var p) = first.spec {
            p.preset = out
            let own = PresetRecipe.defaults(out)
            if !preset.isText { p = own }
            let length = preset.isText ? first.duration : max(rate.snapped(PresetRecipe.length(out)), rate.frameDuration)
            actions.append(Action(target: layer.id, start: first.end + hold, duration: length,
                                  easing: PresetRecipe.easing(out), spec: .preset(p)))
        }
        return PresetPreview(layer: layer, tracks: ActionTracks(actions),
                             period: (actions.last?.end ?? lead) + rest, isSound: isSound, isText: preset.isText)
    }

    func state(at time: Double) -> LayerState { tracks.state(of: layer, at: time) }

    /// Pixels to a point for a curling square's picture.
    static let curlScale: CGFloat = 2
    private static let curlContext = CIContext()
    private static var squares: [Int: CIImage] = [:]

    /// The stand-in, `side` points across, curled as `curl` has it.
    static func curled(_ curl: PageCurl, side: Double) -> CGImage? {
        let pixels = max(Int((side * curlScale).rounded()), 1)
        let size = CGSize(width: pixels, height: pixels)
        let square = squares[pixels] ?? {
            let made = Self.square(pixels: pixels)
            squares[pixels] = made
            return made
        }()
        guard let square, let ground = NSColor(Theme.previewShape).usingColorSpace(.sRGB) else { return nil }
        let back = PageCurlFilter.lifted(RGBA(ground.redComponent, ground.greenComponent, ground.blueComponent))
        guard let output = PageCurlFilter.curled(square, size: size, curl: curl, back: back) else { return nil }
        return curlContext.createCGImage(output, from: CGRect(origin: .zero, size: size))
    }

    private static func square(pixels: Int) -> CIImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(pixels)
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: w), cornerWidth: w * roundness,
                               cornerHeight: w * roundness, transform: nil))
        context.setFillColor(NSColor(Theme.previewShape).cgColor)
        context.fillPath()
        return context.makeImage().map { CIImage(cgImage: $0) }
    }

    /// A text preset's letters at `time`, each as moved from its place; nil
    /// for any other preset.
    func letters(at time: Double) -> [LayerState]? {
        guard isText else { return nil }
        return tracks.textAnimation(of: layer.id, at: time)?.states(count: Self.letters, at: time)
            ?? Array(repeating: TextAnimation.rest, count: Self.letters)
    }
}
