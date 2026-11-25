import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import MotionEvaluation
import MotionExport
import Theme

/// The right panel. At its head, as DialKit's root folder: what is selected,
/// by name, with a line about it, and a chevron that folds the panel away;
/// under that the Design and Animate switch and Export. Below, whatever the
/// selection can have done to it. With nothing selected, that is the
/// composition itself.
struct InspectorPanel: View {
    let store: ProjectStore
    @Bindable var editor: EditorModel
    let controller: EditorController

    var body: some View {
        VStack(spacing: 0) {
            InspectorHead(store: store, editor: editor, controller: controller)
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
        let position = Fold.section("Position"), appearance = Fold.section("Appearance")
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.rowGap) {
                HeaderRow(title: "Position", fold: position) {}
                if position.isOpen {
                    AlignRow(controller: controller)
                    Group {
                        HStack(spacing: Theme.space8) {
                            SharedField(unit: "X", layers: layers, controller: controller, get: { $0.transform.position.x }) { l, v in
                                l.transform.position = Vec2(v, l.transform.position.y)
                            }
                            SharedField(unit: "Y", layers: layers, controller: controller, get: { $0.transform.position.y }) { l, v in
                                l.transform.position = Vec2(l.transform.position.x, v)
                            }
                        }
                        .help("Where each anchor point sits, in pixels. Type +10 or *2 to change each from its own.")
                        SharedField(unit: "Rotation", layers: layers, controller: controller, suffix: "°",
                                    get: { $0.transform.rotation }) { l, v in l.transform.rotation = v }
                            .help("Rotation in degrees, clockwise")
                    }
                    .gridBody()
                }
            }
            .padding(.bottom, position.isOpen ? Theme.panelPad : 0)
            PanelDivider()
            sharedLayout(layers)
            PanelDivider()
            VStack(alignment: .leading, spacing: Theme.rowGap) {
                HeaderRow(title: "Appearance", fold: appearance) {}
                if appearance.isOpen {
                    BlendOpacityRow(blend: blends.count == 1 ? layers[0].blendMode.title : "Mixed",
                                    entries: { blendEntries(layers) }, opacity: shared,
                                    isGroup: layers.contains(where: \.isGroup), mixedOpacity: !alike,
                                    onBegin: { controller.begin("Opacity") },
                                    onChange: { v in controller.update(Self.withOpacity(v, controller.freshLayers(layers.map(\.id)))) },
                                    onEnd: { controller.end() }) { v in
                        controller.perform(.updateLayers(Self.withOpacity(v, controller.freshLayers(layers.map(\.id)))))
                    }
                    .gridBody()
                }
            }
            .padding(.bottom, appearance.isOpen ? Theme.panelPad : 0)
            // The texts among them take type together, whatever else is
            // selected with them (26 November 2026; only when every layer
            // was a text before).
            let texts = layers.filter(\.isText)
            if !texts.isEmpty {
                PanelDivider()
                TextSection(layers: texts, controller: controller)
            }
            if texts.count == layers.count, let text = layers[0].textContent {
                PanelDivider()
                TextFillSection(layers: layers, controller: controller)
                PanelDivider()
                TextStrokeSection(layer: layers[0], text: text, controller: controller, others: Array(layers.dropFirst()))
            }
            // Shapes and frames take fills and strokes together.
            if let look = layers[0].look, layers.allSatisfy({ $0.look != nil }) {
                let others = Array(layers.dropFirst())
                PanelDivider()
                FillSection(layer: layers[0], shape: look, controller: controller, others: others)
                PanelDivider()
                StrokeSection(layer: layers[0], shape: look, controller: controller, others: others)
            }
            // Shadows, blurs and glass go on any layers together.
            PanelDivider()
            EffectsSection(layer: layers[0], controller: controller, others: Array(layers.dropFirst()))
            SelectionColorsSection(ids: layers.map(\.id), controller: controller)
        }
    }

    private static func withOpacity(_ v: Double, _ layers: [Layer]) -> [Layer] {
        layers.map { l in
            var c = l
            c.opacity = v
            return c
        }
    }

    /// Size, scale and corners for several layers: each field reads their
    /// number, or Mixed, and sets it on all of them.
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
        let fold = Fold.section("Layout")
        return VStack(alignment: .leading, spacing: Theme.rowGap) {
            HeaderRow(title: "Layout", fold: fold) {}
            if fold.isOpen { Group {
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
                if cornered {
                    SharedRadiusField(layers: layers, controller: controller)
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
            .gridBody() }
        }
        .padding(.bottom, fold.isOpen ? Theme.panelPad : 0)
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

/// The inspector's head: the selection's name and a line about it, the fold,
/// the mode switch and Export.
private struct InspectorHead: View {
    let store: ProjectStore
    let editor: EditorModel
    let controller: EditorController

    var body: some View {
        let heading = self.heading
        VStack(alignment: .leading, spacing: Theme.panelPad) {
            HStack(alignment: .top, spacing: Theme.space8) {
                VStack(alignment: .leading, spacing: Theme.space2) {
                    Text(heading.title)
                        .font(ThemeFont.title)
                        .foregroundStyle(Theme.textRoot)
                        .lineLimit(1)
                    Text(heading.detail)
                        .font(ThemeFont.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                IconButton(icon: .chevronUp, help: "Hide the inspector (⌘2)") { editor.showInspector = false }
                    .padding(.trailing, Theme.buttonInset - Theme.panelPad)
            }
            // The switch, and beside it Export: always in sight, in both modes.
            HStack(spacing: Theme.space8) {
                SegmentRow(selection: editor.mode, options: [.design, .animate], title: \.title) {
                    controller.setMode($0)
                }
                .help("Design builds the layout, with no animation. Animate adds actions and brings up the timeline. (M)")
                HeadButton(title: "Export") { controller.openExport() }
                    .help("Choose a format and size, see what will be exported, and export it. (⌘E)")
            }
        }
        .padding(Theme.panelPad)
    }

    /// What the head says: in Animate the selected actions, else the
    /// selected layers, else the composition.
    private var heading: (title: String, detail: String) {
        let project = store.project
        let actions = editor.mode == .animate ? controller.selectedActions : []
        if actions.count == 1, let action = actions.first {
            let layer = project.layer(withID: action.targetLayerID)?.name ?? ""
            let end = action.start + action.duration
            let when = action.isInstant ? "at \(Self.seconds(action.start))"
                                        : "\(Self.seconds(action.start)) to \(Self.seconds(end))"
            return (action.name, layer.isEmpty ? when : "\(layer) · \(when)")
        }
        if actions.count > 1 {
            var names: [String] = []
            for action in actions {
                if let name = project.layer(withID: action.targetLayerID)?.name, !names.contains(name) { names.append(name) }
            }
            return ("\(actions.count) Actions", names.joined(separator: ", "))
        }
        let layers = controller.selectedLayers
        if layers.count == 1, let layer = layers.first {
            if case .audio = layer.content { return (layer.name, layer.kindTitle) }
            return (layer.name, "\(layer.kindTitle) · \(Self.number(layer.size.width)) × \(Self.number(layer.size.height))")
        }
        if layers.count > 1 {
            return ("\(layers.count) Layers", layers.map(\.name).joined(separator: ", "))
        }
        let c = project.composition
        return ("Composition", "\(c.width) × \(c.height) · \(c.frameRate.label) fps · \(Self.seconds(c.duration))")
    }

    private static func number(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(0...1)))
    }

    private static func seconds(_ t: Double) -> String {
        t.formatted(.number.precision(.fractionLength(0...2))) + " s"
    }
}

extension Layer {
    /// What kind of layer this is, in a word, for the inspector's head.
    var kindTitle: String {
        switch content {
        case .text: return "Text"
        case .video: return "Video"
        case .audio: return "Sound"
        case .group: return isFrame ? (template != nil ? "Template" : "Frame") : "Group"
        case .shape(let shape):
            if shape.fills.contains(where: { $0.paint.isImage }) { return "Picture" }
            switch shape.geometry {
            case .rectangle: return "Rectangle"
            case .ellipse: return "Ellipse"
            case .line: return "Line"
            case .polygon: return "Polygon"
            case .star: return "Star"
            case .path: return "Path"
            }
        }
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
