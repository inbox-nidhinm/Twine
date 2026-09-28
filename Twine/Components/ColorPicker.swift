import SwiftUI
import AppKit
import MotionModel
import Theme

/// The app's own colour picker, drawn on the panel card like Flip's: a
/// saturation and brightness square, a hue bar, an opacity bar, an eyedropper
/// and the hex. Written here rather than borrowed from a library, and in place
/// of the system colour panel, which is a window of its own in a different
/// material.
///
/// It edits through callbacks rather than a binding, because every change
/// has to reach the document as a command: a drag reports `begin`, then each
/// step, then `end`, and so undoes as one step.
struct ColorPicker: View {
    let color: RGBA
    let onChange: (RGBA) -> Void
    let onBegin: () -> Void
    let onEnd: () -> Void

    @State private var hsb = HSB(h: 0, s: 0, b: 1)
    @State private var alpha = 1.0

    static let squareHeight: CGFloat = 144
    static let bar: CGFloat = 8
    static let thumb: CGFloat = 14
    static let gap: CGFloat = 14

    var body: some View {
        VStack(spacing: Self.gap) {
            SaturationSquare(hsb: hsb, change: { hsb = $0; push() }, began: onBegin, ended: onEnd)
                .frame(height: Self.squareHeight)
            HueBar(hue: hsb.h, change: { hsb.h = $0; push() }, began: onBegin, ended: onEnd)
            AlphaBar(alpha: alpha, color: hsb.rgba(alpha: 1), change: { alpha = $0; push() }, began: onBegin, ended: onEnd)
            HStack(spacing: 8) {
                EyedropperButton { picked in
                    onBegin()
                    onChange(picked)
                    onEnd()
                }
                HexField(color: color) { picked in
                    onBegin()
                    onChange(picked)
                    onEnd()
                }
            }
        }
        .onAppear { pull(color) }
        .onChange(of: color) { _, now in pull(now) }
    }

    private func push() {
        onChange(hsb.rgba(alpha: alpha))
    }

    /// Takes a colour from outside, keeping the hue where it was for greys and
    /// black, which have none of their own, so the square does not jump to red.
    private func pull(_ c: RGBA) {
        guard !hsb.rgba(alpha: alpha).near(c) else { return }
        let next = HSB(c)
        hsb = HSB(h: next.s > 0.0001 && next.b > 0.0001 ? next.h : hsb.h,
                  s: next.b > 0.0001 ? next.s : hsb.s, b: next.b)
        alpha = c.a
    }
}

/// Hue, saturation and brightness, each 0 to 1.
struct HSB: Equatable {
    var h: Double
    var s: Double
    var b: Double

    init(h: Double, s: Double, b: Double) {
        self.h = h
        self.s = s
        self.b = b
    }

    init(_ c: RGBA) {
        let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b)
        let delta = maxC - minC
        b = maxC
        s = maxC > 0 ? delta / maxC : 0
        var hue = 0.0
        if delta > 0 {
            if maxC == c.r { hue = (c.g - c.b) / delta }
            else if maxC == c.g { hue = 2 + (c.b - c.r) / delta }
            else { hue = 4 + (c.r - c.g) / delta }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        h = hue
    }

    func rgba(alpha: Double) -> RGBA {
        let i = Int((h * 6).rounded(.down)) % 6
        let f = h * 6 - (h * 6).rounded(.down)
        let p = b * (1 - s), q = b * (1 - f * s), t = b * (1 - (1 - f) * s)
        switch i {
        case 0: return RGBA(b, t, p, alpha)
        case 1: return RGBA(q, b, p, alpha)
        case 2: return RGBA(p, b, t, alpha)
        case 3: return RGBA(p, q, b, alpha)
        case 4: return RGBA(t, p, b, alpha)
        default: return RGBA(b, p, q, alpha)
        }
    }
}

extension RGBA {
    func near(_ o: RGBA) -> Bool {
        abs(r - o.r) < 0.004 && abs(g - o.g) < 0.004 && abs(b - o.b) < 0.004 && abs(a - o.a) < 0.004
    }
}

/// Saturation across, brightness up, for the current hue.
private struct SaturationSquare: View {
    let hsb: HSB
    let change: (HSB) -> Void
    let began: () -> Void
    let ended: () -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let hue = HSB(h: hsb.h, s: 1, b: 1).rgba(alpha: 1).opaque
            ZStack(alignment: .topLeading) {
                Rectangle().fill(LinearGradient(colors: [.white, hue], startPoint: .leading, endPoint: .trailing))
                Rectangle().fill(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                Circle()
                    .strokeBorder(Theme.pickerRing, lineWidth: 2)
                    .background(Circle().fill(hsb.rgba(alpha: 1).opaque))
                    .shadow(color: Theme.pickerRingShadow, radius: 1)
                    .frame(width: ColorPicker.thumb, height: ColorPicker.thumb)
                    .offset(x: hsb.s * geo.size.width - ColorPicker.thumb / 2,
                            y: (1 - hsb.b) * geo.size.height - ColorPicker.thumb / 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusControl))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !dragging { dragging = true; began() }
                    let s = min(max(g.location.x / max(geo.size.width, 1), 0), 1)
                    let b = 1 - min(max(g.location.y / max(geo.size.height, 1), 0), 1)
                    change(HSB(h: hsb.h, s: s, b: b))
                }
                .onEnded { _ in dragging = false; ended() })
        }
    }
}

/// A thin bar with a round thumb, shared by hue and opacity.
private struct PickerBar<Track: View>: View {
    let value: Double
    let thumbFill: Color
    @ViewBuilder var track: () -> Track
    let change: (Double) -> Void
    let began: () -> Void
    let ended: () -> Void

    @State private var dragging = false

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - ColorPicker.thumb, 1)
            ZStack(alignment: .leading) {
                track()
                    .frame(height: ColorPicker.bar)
                    .clipShape(Capsule())
                    .overlay(Capsule().strokeBorder(Theme.edge, lineWidth: 1))
                    .padding(.horizontal, ColorPicker.thumb / 2)
                Circle()
                    .strokeBorder(Theme.pickerRing, lineWidth: 2)
                    .background(Circle().fill(thumbFill))
                    .shadow(color: Theme.pickerRingShadow, radius: 1)
                    .frame(width: ColorPicker.thumb, height: ColorPicker.thumb)
                    .offset(x: value * travel)
            }
            .frame(height: ColorPicker.thumb)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { g in
                    if !dragging { dragging = true; began() }
                    change(min(max((g.location.x - ColorPicker.thumb / 2) / travel, 0), 1))
                }
                .onEnded { _ in dragging = false; ended() })
        }
        .frame(height: ColorPicker.thumb)
    }
}

private struct HueBar: View {
    let hue: Double
    let change: (Double) -> Void
    let began: () -> Void
    let ended: () -> Void

    var body: some View {
        let stops = stride(from: 0.0, through: 1, by: 1.0 / 6).map { HSB(h: min($0, 0.9999), s: 1, b: 1).rgba(alpha: 1).opaque }
        PickerBar(value: hue, thumbFill: HSB(h: hue, s: 1, b: 1).rgba(alpha: 1).opaque,
                  track: { LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing) },
                  change: change, began: began, ended: ended)
    }
}

private struct AlphaBar: View {
    let alpha: Double
    let color: RGBA
    let change: (Double) -> Void
    let began: () -> Void
    let ended: () -> Void

    var body: some View {
        PickerBar(value: alpha, thumbFill: color.opaque.opacity(alpha),
                  track: {
                      ZStack {
                          Checkerboard(cell: 4)
                          LinearGradient(colors: [color.opaque.opacity(0), color.opaque],
                                         startPoint: .leading, endPoint: .trailing)
                      }
                  },
                  change: change, began: began, ended: ended)
    }
}

/// Picks a colour from anywhere on screen with the system's loupe.
private struct EyedropperButton: View {
    let pick: (RGBA) -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            NSColorSampler().show { sampled in
                guard let sampled else { return }
                let c = RGBA(sampled)
                MainActor.assumeIsolated { pick(c) }
            }
        } label: {
            IconView(.eyedropper, size: 15)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: Theme.control, height: Theme.control)
                .background(RoundedRectangle(cornerRadius: Theme.radiusControl)
                    .fill(hovering ? Theme.border : Theme.panelRaised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Pick a colour from the screen")
    }
}
