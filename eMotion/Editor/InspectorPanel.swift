import SwiftUI
import AppKit
import MotionModel
import MotionEditing
import Theme

/// The right panel. The Design and Animate switch sits at its head; below it,
/// whatever the selection can have done to it. With nothing selected, that is
/// the composition itself.
struct InspectorPanel: View {
    let store: ProjectStore
    @Bindable var editor: EditorModel
    let controller: EditorController

    @State private var compositionOpen = true
    @State private var customRate = false

    var body: some View {
        VStack(spacing: 0) {
            SegmentRow(selection: editor.mode, options: EditorModel.Mode.allCases, title: \.title) {
                editor.mode = $0
            }
            .padding(Theme.panelPad)
            .help("Design builds the frame. Animate brings up the timeline. (⌥⌘1, ⌥⌘2)")

            PanelDivider()
            ScrollView {
                VStack(spacing: 0) {
                    let selected = controller.selectedLayers
                    if selected.count == 1, let layer = selected.first {
                        LayerInspector(layer: layer, controller: controller, time: editor.time)
                            .id(layer.id)
                    } else if selected.count > 1 {
                        multipleSelection(selected)
                    } else {
                        compositionSection
                        PanelDivider()
                    }
                }
            }
        }
    }

    // MARK: Several layers

    /// What several layers have in common to change together.
    private func multipleSelection(_ layers: [Layer]) -> some View {
        let values = layers.map { $0.opacity.value(at: editor.time) }
        let shared = values.allSatisfy { abs($0 - values[0]) < 1e-9 } ? values[0] : values.max() ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            HeaderRow(title: "Layers") {}
            SliderRow(label: "Opacity", value: shared * 100, range: 0...100, readout: { "\(Int($0.rounded()))%" },
                      onChange: { v in
                          controller.update(layers.map { l in
                              var c = l
                              c.opacity = c.opacity.designEdited(to: v / 100, at: editor.time)
                              return c
                          })
                      },
                      onBegin: { controller.begin("Opacity") },
                      onEnd: { controller.end() })
                .padding(.horizontal, Theme.panelPad)
        }
        .padding(.bottom, Theme.panelPad)
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
                .padding(.horizontal, Theme.panelPad)
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
                ColorWell(color: composition.background.color,
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
