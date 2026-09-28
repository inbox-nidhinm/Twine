import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionExport
import Theme

/// The right panel. The Design and Animate switch sits at its head; below it,
/// whatever the selection can have done to it. With nothing selected, that is
/// the composition itself. The Export button sits at the foot, always.
struct InspectorPanel: View {
    let store: ProjectStore
    @Bindable var editor: EditorModel
    let controller: EditorController

    @State private var compositionOpen = true
    @State private var customRate = false

    var body: some View {
        VStack(spacing: 0) {
            SegmentRow(selection: editor.mode, options: EditorModel.Mode.allCases, title: \.title) {
                controller.setMode($0)
            }
            .padding(Theme.panelPad)
            .help("Design builds the layout, with no animation. Animate adds actions and brings up the timeline. (M)")

            PanelDivider()
            ScrollView {
                VStack(spacing: 0) {
                    // The two modes never share a control.
                    switch editor.mode {
                    case .design: designContent
                    case .animate: AnimationInspector(controller: controller, editor: editor)
                    }
                }
            }
            // Last in the panel, in both modes, whatever is selected.
            PanelDivider()
            PrimaryButton(title: "Export") { controller.openExport() }
                .padding(Theme.panelPad)
                .help("Choose a format and size, see what will be exported, and export it. (⌘E)")
        }
    }

    /// Design mode: the selected layer as designed, what several layers
    /// share, or with nothing selected, the composition.
    @ViewBuilder private var designContent: some View {
        let selected = controller.selectedLayers
        if selected.count == 1, let layer = selected.first {
            LayerInspector(layer: layer, controller: controller)
                .id(layer.id)
        } else if selected.count > 1 {
            multipleSelection(selected)
        } else {
            compositionSection
            PanelDivider()
        }
    }

    // MARK: Several layers

    /// What several layers have in common to change together: lining them
    /// up, and how they mix and show.
    private func multipleSelection(_ layers: [Layer]) -> some View {
        let values = layers.map(\.opacity)
        let shared = values.allSatisfy { abs($0 - values[0]) < 1e-9 } ? values[0] : values.max() ?? 1
        let blends = Set(layers.map(\.blendMode))
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HeaderRow(title: "Position") {}
                AlignRow(controller: controller)
            }
            .padding(.bottom, Theme.panelPad)
            PanelDivider()
            VStack(alignment: .leading, spacing: 8) {
                HeaderRow(title: "Appearance") {}
                BlendOpacityRow(blend: blends.count == 1 ? layers[0].blendMode.title : "Mixed",
                                entries: { blendEntries(layers) }, opacity: shared,
                                isGroup: layers.contains(where: \.isGroup)) { v in
                    controller.perform(.updateLayers(layers.map { l in
                        var c = l
                        c.opacity = v
                        return c
                    }))
                }
                .gridBody()
            }
            .padding(.bottom, Theme.panelPad)
        }
    }

    private func blendEntries(_ layers: [Layer]) -> [MenuEntry] {
        var entries: [MenuEntry] = []
        for (i, group) in BlendMode.groups.enumerated() {
            if i > 0 { entries.append(.separator) }
            entries += group.map { mode in
                .item(mode.title, checked: layers.allSatisfy { $0.blendMode == mode }) {
                    controller.perform(.updateLayers(layers.map { l in
                        var c = l
                        c.blendMode = mode
                        return c
                    }))
                }
            }
        }
        return entries
    }

    // MARK: Composition

    private var composition: Composition { store.project.composition }

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Composition", isOpen: compositionOpen) { compositionOpen.toggle() }
            if compositionOpen {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        UnitField(unit: "W", value: Double(composition.width), accepts: Self.validDimension) { v in
                            edit { $0.width = Int(v.rounded()) }
                        }
                        .help("Width in pixels")
                        UnitField(unit: "H", value: Double(composition.height), accepts: Self.validDimension) { v in
                            edit { $0.height = Int(v.rounded()) }
                        }
                        .help("Height in pixels")
                    }

                    MenuRow(label: "Frame rate", value: "\(composition.frameRate.label) fps", entries: rateEntries)

                    if customRate || !FrameRate.presets.contains(composition.frameRate) {
                        LabeledRow(label: "Custom") {
                            UnitField(value: composition.frameRate.perSecond, decimals: 3, suffix: "fps",
                                      accepts: { $0 > 0 && $0 <= 1000 }) { v in
                                edit { $0.frameRate = Self.rate(from: v) }
                            }
                        }
                    }

                    LabeledRow(label: "Duration") {
                        UnitField(value: composition.duration, decimals: 3, suffix: "s", accepts: { $0 > 0 }) { v in
                            edit { $0.duration = v }
                        }
                        .help("Length in seconds")
                    }

                    background
                }
                .gridBody()
                .padding(.bottom, Theme.panelPad)
                .transition(.opacity)
            }
        }
    }

    private var background: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Background")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                ColorWell(color: composition.background.color, title: "Background",
                          onChange: { color in
                              var c = composition
                              c.background.color = color
                              try? store.updateContinuousChange(.setComposition(c))
                          },
                          onBegin: { store.beginContinuousChange("Background Colour") },
                          onEnd: { store.endContinuousChange() })
                HexField(color: composition.background.color) { color in
                    edit { $0.background.color = color }
                }
            }
            ToggleRow(label: "Transparent", isOn: composition.background.isTransparent) {
                edit { $0.background.isTransparent.toggle() }
            }
            .help("Exports that support it keep an alpha channel. The canvas shows a checkerboard.")
        }
    }

    private func rateEntries() -> [MenuEntry] {
        var entries = FrameRate.presets.map { rate in
            MenuEntry.item("\(rate.label) fps", checked: rate == composition.frameRate && !customRate) {
                customRate = false
                edit { $0.frameRate = rate }
            }
        }
        entries.append(.separator)
        entries.append(.item("Custom", checked: customRate || !FrameRate.presets.contains(composition.frameRate)) {
            customRate = true
        })
        return entries
    }

    private func edit(_ change: (inout Composition) -> Void) {
        var c = composition
        change(&c)
        do {
            try store.perform(.setComposition(c))
        } catch {
            NSSound.beep()
        }
    }

    private static func validDimension(_ v: Double) -> Bool { v >= 1 && v <= 16384 }

    /// A typed rate as an exact fraction. The three broadcast rates are
    /// recognised from their usual decimals, since 29.97 is really 30000/1001.
    static func rate(from fps: Double) -> FrameRate {
        for broadcast in [FrameRate.fps23_976, .fps29_97, .fps59_94] where abs(broadcast.perSecond - fps) < 0.006 {
            return broadcast
        }
        if abs(fps - fps.rounded()) < 0.0005 { return FrameRate(frames: Int(fps.rounded())) }
        let frames = Int((fps * 1000).rounded())
        let divisor = gcd(frames, 1000)
        return FrameRate(frames: frames / divisor, seconds: 1000 / divisor)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}

/// Aligning and spacing the selection, at the head of the Position section:
/// one layer lines up with the composition, several with each other. The
/// three horizontal and the three vertical alignments sit in two trays, as
/// Figma has them; spacing, which only means something for three or more
/// layers, is a menu at the end.
struct AlignRow: View {
    let controller: EditorController

    @Environment(MenuHost.self) private var menus
    @State private var distributeFrame: CGRect = .zero

    var body: some View {
        HStack(spacing: 8) {
            tray([.left, .centerX, .right])
            tray([.top, .centerY, .bottom])
        }
        .rowButton {
            IconButton(icon: .distributeV, help: "Distribute: equal spaces between three or more layers") {
                menus.show([
                    .item("Distribute Horizontally  ⌃⌥H", disabled: !controller.canDistribute) { controller.distribute(.x) },
                    .item("Distribute Vertically  ⌃⌥V", disabled: !controller.canDistribute) { controller.distribute(.y) },
                ], at: CGPoint(x: distributeFrame.maxX - Theme.menuMinWidth, y: distributeFrame.maxY + 4))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { distributeFrame = $0 }
        }
        .gridBody()
    }

    private func tray(_ edges: [MotionEditing.Alignment.Edge]) -> some View {
        // The gaps between the buttons show the panel through them, which
        // draws the rules between them.
        HStack(spacing: 1) {
            ForEach(edges, id: \.self) { edge in
                TrayButton(icon: edge.icon, help: "\(edge.title) (\(edge.shortcut))") { controller.align(edge) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        .disabled(!controller.canAlign)
    }
}

/// One button in a tray of them: raised, lighter under the pointer.
private struct TrayButton: View {
    let icon: Icon
    let help: String
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 15)
                .foregroundStyle(hovering && isEnabled ? Theme.textPrimary : Theme.textSecondary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.control)
                .background(hovering && isEnabled ? Theme.panelHover : Theme.panelRaised)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
