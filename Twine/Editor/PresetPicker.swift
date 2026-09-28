import SwiftUI
import MotionModel
import MotionEditing
import MotionEvaluation
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

/// Every preset the selection can take, grouped by what it does, each on a
/// tile that plays it, so what you pick is what you saw.
struct PresetPicker: View {
    let presets: [Preset]
    let pick: (Preset) -> Void
    let close: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderRow(title: "Presets") {
                IconButton(icon: .close, help: "Back to actions") { close() }
            }
            ForEach(PresetCategory.allCases, id: \.self) { category in
                let items = presets.filter { $0.category == category }
                if !items.isEmpty {
                    Text(category.title)
                        .font(ThemeFont.label)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.panelPad)
                        .frame(height: Theme.panelRow, alignment: .bottomLeading)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { preset in
                            PresetTile(preset: preset) { pick(preset) }
                        }
                    }
                    .padding(.horizontal, Theme.panelPad)
                    .padding(.top, 6)
                    .padding(.bottom, Theme.panelPad)
                }
            }
        }
    }
}

private struct PresetTile: View {
    let preset: Preset
    let pick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { PresetThumbnail(kind: preset.kind) }
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
        .help("Adds \(preset.name) at the playhead")
    }
}

/// A preset playing on a stand-in, over and over. The motion is the real
/// one, worked out by the same rules that play it on the canvas, so the
/// tile can never show something the preset does not do.
struct PresetThumbnail: View {
    let kind: PresetKind

    var body: some View {
        let preview = PresetPreview.of(kind)
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: preview.period)
            let state = preview.state(at: t)
            Canvas { context, size in
                if preview.isSound {
                    Self.drawSound(state, in: &context, size: size)
                } else {
                    Self.drawShape(state, in: &context, size: size)
                }
            }
        }
    }

    private static func drawShape(_ state: LayerState, in context: inout GraphicsContext, size: CGSize) {
        guard state.isShown, state.opacity > 0.001,
              abs(state.scale.x) > 0.0001, abs(state.scale.y) > 0.0001 else { return }
        let k = size.width / PresetPreview.scene
        context.opacity = state.opacity
        // Blur is stored as Figma has it, twice the spread.
        if state.layerBlur > 0 { context.addFilter(.blur(radius: state.layerBlur / 2 * k)) }
        context.translateBy(x: state.position.x * k, y: state.position.y * k)
        context.rotate(by: .degrees(state.rotation))
        context.scaleBy(x: state.scale.x, y: state.scale.y)
        let w = state.size.width * k, h = state.size.height * k
        let box = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
        context.fill(RoundedRectangle(cornerRadius: w * PresetPreview.roundness).path(in: box),
                     with: .color(Theme.previewShape))
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
    /// An empty moment before it plays and a rest after, so each loop reads
    /// as one go.
    private static let lead = 0.35
    private static let rest = 0.7

    let layer: Layer
    let tracks: ActionTracks
    let period: Double
    let isSound: Bool

    private static var cache: [PresetKind: PresetPreview] = [:]

    static func of(_ kind: PresetKind) -> PresetPreview {
        if let known = cache[kind] { return known }
        let made = make(kind)
        cache[kind] = made
        return made
    }

    private static func make(_ kind: PresetKind) -> PresetPreview {
        let preset = Presets.preset(kind)
        let isSound = preset.category == .sound
        let corner = Vec2((scene - side) / 2, (scene - side) / 2)
        let layer = isSound
            ? Layer(name: preset.name, content: .audio(AudioContent(mediaID: UUID())),
                    size: Size2(side, side), position: Vec2(scene / 2, scene / 2))
            : LayerFactory.shape(.rectangle, in: Box(origin: corner, size: Size2(side, side)), name: preset.name)
        let action = Presets.action(preset, for: layer, at: lead, frameRate: FrameRate(frames: 60))
        return PresetPreview(layer: layer, tracks: ActionTracks([action]),
                             period: lead + action.duration + rest, isSound: isSound)
    }

    func state(at time: Double) -> LayerState { tracks.state(of: layer, at: time) }
}
