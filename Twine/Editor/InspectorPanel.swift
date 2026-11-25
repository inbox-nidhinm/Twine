import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionExport
import Theme

/// The right panel. The Animate and Design switch sits at its head; below it,
/// whatever the selection can have done to it. With nothing selected, that is
/// the composition itself. Export sits beside the switch, always.
struct InspectorPanel: View {
    let store: ProjectStore
    @Bindable var editor: EditorModel
    let controller: EditorController

    var body: some View {
        VStack(spacing: 0) {
            // The switch, and beside it Export: always in sight, in both
            // modes, without being the loudest thing on screen.
            HStack(spacing: Theme.space8) {
                SegmentRow(selection: editor.mode, options: EditorModel.Mode.allCases, title: \.title) {
                    controller.setMode($0)
                }
                .help("Animate adds actions and brings up the timeline. Design builds the layout, with no animation. (M)")
                HeadButton(title: "Export") { controller.openExport() }
                    .help("Choose a format and size, see what will be exported, and export it. (⌘E)")
            }
            .padding(Theme.panelPad)

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
            CompositionSection(store: store)
            PanelDivider()
        }
    }

    // MARK: Several layers

    /// What several layers have in common to change together: lining them
    /// up, and how they mix and show; for texts, their type and colour too;
    /// and every colour they use.
    private func multipleSelection(_ layers: [Layer]) -> some View {
        let values = layers.map(\.opacity)
        let alike = values.allSatisfy { abs($0 - values[0]) < 1e-9 }
        let shared = alike ? values[0] : values.max() ?? 1
        let blends = Set(layers.map(\.blendMode))
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.space8) {
                HeaderRow(title: "Position") {}
                AlignRow(controller: controller)
                HStack(spacing: Theme.space8) {
                    SharedField(unit: "X", layers: layers, controller: controller, get: { $0.transform.position.x }) { l, v in
                        l.transform.position = Vec2(v, l.transform.position.y)
                    }
                    SharedField(unit: "Y", layers: layers, controller: controller, get: { $0.transform.position.y }) { l, v in
                        l.transform.position = Vec2(l.transform.position.x, v)
                    }
                }
                .help("Where each anchor point sits, in pixels. Type +10 or *2 to change each from its own.")
                .gridBody()
            }
            .padding(.bottom, Theme.panelPad)
            PanelDivider()
            sharedLayout(layers)
            PanelDivider()
            VStack(alignment: .leading, spacing: Theme.space8) {
                HeaderRow(title: "Appearance") {}
                BlendOpacityRow(blend: blends.count == 1 ? layers[0].blendMode.title : "Mixed",
                                entries: { blendEntries(layers) }, opacity: shared,
                                isGroup: layers.contains(where: \.isGroup), mixedOpacity: !alike) { v in
                    controller.perform(.updateLayers(layers.map { l in
                        var c = l
                        c.opacity = v
                        return c
                    }))
                }
                .gridBody()
            }
            .padding(.bottom, Theme.panelPad)
            // The texts among them take type together, whatever else is
            // selected with them (26 November 2026; only when every layer
            // was a text before).
            let texts = layers.filter(\.isText)
            if !texts.isEmpty {
                PanelDivider()
                TextSection(layers: texts, controller: controller)
            }
            if texts.count == layers.count {
                PanelDivider()
                TextFillSection(layers: layers, controller: controller)
            }
            // Shapes and frames take fills and strokes together.
            if let look = layers[0].look, layers.allSatisfy({ $0.look != nil }) {
                let others = Array(layers.dropFirst())
                PanelDivider()
                FillSection(layer: layers[0], shape: look, controller: controller, others: others)
                PanelDivider()
                StrokeSection(layer: layers[0], shape: look, controller: controller, others: others)
            }
            SelectionColorsSection(ids: layers.map(\.id), controller: controller)
        }
    }

    /// Size, scale, turn and corners for several layers: each field reads
    /// their number, or Mixed, and sets it on all of them.
    private func sharedLayout(_ layers: [Layer]) -> some View {
        // A group's size is only where it was made.
        let sized = layers.allSatisfy { !$0.isGroup || $0.isFrame }
        let cornered = layers.allSatisfy { layer in
            switch layer.look?.geometry {
            case .rectangle, .polygon, .star, .path: true
            default: false
            }
        }
        let groups = layers.compactMap { layer -> GroupContent? in
            if case .group(let g) = layer.content { return g }
            return nil
        }
        return VStack(alignment: .leading, spacing: Theme.space8) {
            HeaderRow(title: "Layout") {}
            Group {
                if sized {
                    HStack(spacing: Theme.space8) {
                        SharedField(unit: "W", layers: layers, controller: controller, accepts: { $0 >= 0 },
                                    get: { $0.size.width }) { l, v in l = l.resized(toWidth: v) }
                        SharedField(unit: "H", layers: layers, controller: controller, accepts: { $0 >= 0 },
                                    get: { $0.size.height }) { l, v in l = l.resized(toHeight: v) }
                    }
                }
                HStack(spacing: Theme.space8) {
                    SharedField(unit: "SX", layers: layers, controller: controller, suffix: "%",
                                get: { $0.transform.scale.x * 100 }) { l, v in
                        let s = l.transform.scale
                        let y = l.transform.isScaleLinked ? (s.x != 0 ? s.y / s.x * v / 100 : v / 100) : s.y
                        l.transform.scale = Vec2(v / 100, y)
                    }
                    .help("Scale across")
                    SharedField(unit: "SY", layers: layers, controller: controller, suffix: "%",
                                get: { $0.transform.scale.y * 100 }) { l, v in
                        let s = l.transform.scale
                        let x = l.transform.isScaleLinked ? (s.y != 0 ? s.x / s.y * v / 100 : v / 100) : s.x
                        l.transform.scale = Vec2(x, v / 100)
                    }
                    .help("Scale down")
                }
                HStack(spacing: Theme.space8) {
                    SharedField(unit: "R", layers: layers, controller: controller, suffix: "°",
                                get: { $0.transform.rotation }) { l, v in l.transform.rotation = v }
                        .help("Rotation in degrees, clockwise")
                    if cornered {
                        SharedRadiusField(layers: layers, controller: controller)
                    } else {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
                if groups.count == layers.count {
                    let clips = groups.allSatisfy(\.clipsContent)
                    CheckRow(label: "Clip content", isOn: clips) {
                        controller.perform(controller.layerUpdate(controller.freshLayers(layers.map(\.id)).map { layer in
                            var l = layer
                            if case .group(var g) = l.content {
                                g.clipsContent = !clips
                                l.content = .group(g)
                            }
                            return l
                        }))
                    }
                    .help("Hides whatever lies outside each one's box.")
                }
            }
            .gridBody()
        }
        .padding(.bottom, Theme.panelPad)
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
}

/// One number of several layers, in a field that sets it on all of them:
/// it reads the number they share, or Mixed. A plain number goes to every
/// layer; a change typed with a sign first (`+10`, `*2`) goes to each from
/// its own number.
private struct SharedField: View {
    let unit: String
    let layers: [Layer]
    let controller: EditorController
    var suffix = ""
    var accepts: (Double) -> Bool = { _ in true }
    let get: (Layer) -> Double
    let set: (inout Layer, Double) -> Void

    var body: some View {
        let values = layers.map(get)
        let alike = values.allSatisfy { abs($0 - values[0]) < 1e-9 }
        UnitField(unit: unit, value: values[0], decimals: 1, suffix: suffix, accepts: accepts, mixed: !alike,
                  commitEach: { change in
                      edit { l in
                          let v = change(get(l))
                          if UnitField.holds(v), accepts(v) { set(&l, v) }
                      }
                  }) { v in
            edit { set(&$0, v) }
        }
    }

    private func edit(_ change: (inout Layer) -> Void) {
        let edited = controller.freshLayers(layers.map(\.id)).map { layer -> Layer in
            var l = layer
            change(&l)
            return l
        }
        guard !edited.isEmpty else { return }
        controller.perform(controller.layerUpdate(edited))
    }
}

/// The corner radius of several shapes: the largest of each one's corners,
/// set on every corner of all of them, their Path actions following as
/// they do for one layer.
private struct SharedRadiusField: View {
    let layers: [Layer]
    let controller: EditorController

    var body: some View {
        let values = layers.map(Self.radius)
        let alike = values.allSatisfy { abs($0 - values[0]) < 1e-9 }
        UnitField(icon: .cornerTopLeft, value: values[0], decimals: 1, accepts: { $0 >= 0 }, mixed: !alike,
                  commitEach: { change in set { max(change(Self.radius($0)), 0) } }) { v in
            set { _ in v }
        }
        .help("Corner radius, in pixels")
    }

    private static func radius(_ layer: Layer) -> Double {
        if let largest = CornerEditing.radii(of: layer, at: nil).max() { return largest }
        if case .rectangle(let r)? = layer.look?.geometry { return max(r.topLeft, r.topRight, r.bottomRight, r.bottomLeft) }
        return 0
    }

    private func set(_ radius: (Layer) -> Double) {
        var edited: [Layer] = []
        var moved: [Action] = []
        for layer in controller.freshLayers(layers.map(\.id)) {
            let v = radius(layer)
            guard UnitField.holds(v) else { continue }
            if CornerEditing.hasCorners(layer) {
                let (changed, actions) = CornerEditing.setting(v, at: nil, of: layer, actions: controller.project.actions)
                edited.append(changed)
                moved += actions
            } else if var look = layer.look, case .rectangle = look.geometry {
                var l = layer
                look.geometry = .rectangle(cornerRadii: CornerRadii(all: v))
                l.look = look
                edited.append(l)
            }
        }
        guard !edited.isEmpty else { return }
        let update = controller.layerUpdate(edited)
        controller.perform(moved.isEmpty ? .batch([update], name: "Corner Radius")
                                         : .batch([update, .updateActions(moved)], name: "Corner Radius"))
    }
}

/// The composition's own settings: its size, frame rate, length and
/// background. Shown with nothing selected, in both modes.
struct CompositionSection: View {
    let store: ProjectStore

    @State private var compositionOpen = true
    @State private var customRate = false

    private var composition: Composition { store.project.composition }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Composition", isOpen: compositionOpen) { compositionOpen.toggle() }
            if compositionOpen {
                VStack(alignment: .leading, spacing: Theme.space10) {
                    HStack(spacing: Theme.space8) {
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
                        UnitField(unit: "Custom", value: composition.frameRate.perSecond, decimals: 3, suffix: "fps",
                                  accepts: { $0 >= 0.001 && $0 <= 1000 }) { v in
                            edit { $0.frameRate = Self.rate(from: v) }
                        }
                        .help("Frames a second")
                    }

                    UnitField(unit: "Duration", value: composition.duration, decimals: 3, suffix: "s",
                              accepts: { $0 > 0 && $0 <= Composition.longest }) { v in
                        edit { $0.duration = v }
                    }
                    .help("Length in seconds")

                    background
                }
                .gridBody()
                .padding(.bottom, Theme.panelPad)
                .transition(.opacity)
            }
        }
    }

    private var background: some View {
        VStack(alignment: .leading, spacing: Theme.space6) {
            Text("Background")
                .font(ThemeFont.label)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: Theme.space8) {
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
        // Never no frames at all: a rate that rounds to zero is not a rate,
        // and `FrameRate` stops the app rather than hold one.
        if fps.rounded() >= 1, abs(fps - fps.rounded()) < 0.0005 { return FrameRate(frames: Int(saturating: fps.rounded())) }
        let frames = max(Int(saturating: (fps * 1000).rounded()), 1)
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
        HStack(spacing: Theme.space8) {
            tray([.left, .centerX, .right])
            tray([.top, .centerY, .bottom])
        }
        .rowButton {
            IconButton(icon: .distributeV, help: "Distribute: equal spaces between three or more layers") {
                menus.show([
                    .item("Distribute Horizontally", disabled: !controller.canDistribute, shortcut: "⌃⌥H") { controller.distribute(.x) },
                    .item("Distribute Vertically", disabled: !controller.canDistribute, shortcut: "⌃⌥V") { controller.distribute(.y) },
                ], at: CGPoint(x: distributeFrame.maxX - Theme.menuMinWidth, y: distributeFrame.maxY + 4))
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { distributeFrame = $0 }
        }
        .gridBody()
    }

    private func tray(_ edges: [MotionEditing.Alignment.Edge]) -> some View {
        // The gaps between the buttons show the panel through them, which
        // draws the rules between them.
        HStack(spacing: Theme.space1) {
            ForEach(edges, id: \.self) { edge in
                TrayButton(icon: edge.icon, help: "\(edge.title) (\(edge.shortcut))") { controller.align(edge) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
        .disabled(!controller.canAlign)
    }
}

/// One button in a tray of them: raised, lighter under the pointer, and on
/// `chosen` when it is the choice in force.
struct TrayButton: View {
    let icon: Icon
    let help: String
    var isOn = false
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            IconView(icon, size: Theme.iconRow)
                .foregroundStyle(isOn || (hovering && isEnabled) ? Theme.textPrimary : Theme.textSecondary)
                .opacity(isEnabled ? 1 : 0.4)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.control)
                .background(isOn ? Theme.chosen : hovering && isEnabled ? Theme.panelHover : Theme.panelRaised)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
