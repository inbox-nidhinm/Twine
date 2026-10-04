import Foundation
import MotionModel

/// A layer's look, copied to paint onto others: Copy Style and Paste Style
/// (⌥⌘C, ⌥⌘V), as Figma's Copy and Paste Properties (4 October 2026). Every
/// layer takes the opacity, blend mode and effects; a shape or frame takes
/// fills and strokes; a text takes another text's type (font, weight, size,
/// alignment, spacing), colour and stroke, never its words. Between text
/// and shapes the colour and stroke carry across: a text's colour becomes a
/// shape's fill, and a shape's top fill a text's colour.
public struct LayerStyle: Codable, Sendable, Equatable {
    public var opacity: Double
    public var blendMode: BlendMode
    public var effects: [Effect]
    /// A shape's or frame's fills and strokes; nil from any other layer.
    public var fills: [Fill]?
    public var strokes: [Stroke]?
    /// A text's type, colour and stroke; nil from any other layer.
    public var text: TextLook?

    /// What a text's style is beside its words.
    public struct TextLook: Codable, Sendable, Equatable {
        public var fontFamily: String
        public var fontWeight: Int
        public var fontSize: Double
        public var color: RGBA
        public var hidesFill: Bool?
        public var alignment: TextAlignment
        public var letterSpacing: Double
        public var lineHeight: Double?
        public var stroke: Stroke?
    }

    public init(of layer: Layer) {
        opacity = layer.opacity
        blendMode = layer.blendMode
        effects = layer.effects
        if let look = layer.look {
            fills = look.fills
            strokes = look.strokes
        }
        if case .text(let t) = layer.content {
            text = TextLook(fontFamily: t.fontFamily, fontWeight: t.fontWeight, fontSize: t.fontSize, color: t.color,
                            hidesFill: t.hidesFill, alignment: t.alignment, letterSpacing: t.letterSpacing,
                            lineHeight: t.lineHeight, stroke: t.stroke)
        }
    }

    /// Whether `layer` can take a style: anything but a sound.
    public static func takes(_ layer: Layer) -> Bool {
        if case .audio = layer.content { return false }
        return true
    }

    /// `layer` painted with this style, every fill, stroke and effect under
    /// a new id. Picture fills whose file is not in `media` (copied from
    /// another project) are left out, as there is nothing to show. A sound
    /// comes back as it was.
    public func applied(to layer: Layer, media: Set<UUID>) -> Layer {
        guard Self.takes(layer) else { return layer }
        var l = layer
        l.opacity = opacity
        l.blendMode = blendMode
        l.effects = effects.map { Effect(isEnabled: $0.isEnabled, kind: $0.kind) }
        if var look = l.look, let (fills, strokes) = lookParts(media: media) {
            look.fills = fills
            look.strokes = strokes
            l.look = look
        }
        if case .text(var t) = l.content {
            if let text {
                t.fontFamily = text.fontFamily
                t.fontWeight = text.fontWeight
                t.fontSize = text.fontSize
                t.color = text.color
                t.hidesFill = text.hidesFill
                t.alignment = text.alignment
                t.letterSpacing = text.letterSpacing
                t.lineHeight = text.lineHeight
                t.stroke = text.stroke?.withNewID()
            } else if let fills, let strokes {
                // A shape's top fill that has a colour is the text's colour;
                // with none showing, the text's fill is switched off.
                let shown = fills.filter(\.isEnabled)
                if let color = shown.last.flatMap({ Self.color(of: $0.paint) }) {
                    t.color = color
                    t.hidesFill = nil
                } else if shown.isEmpty {
                    t.hidesFill = true
                }
                // Text strokes are one colour.
                t.stroke = strokes.first.map { s in
                    var stroke = s.withNewID()
                    stroke.paint = .solid(Self.color(of: s.paint) ?? .black)
                    return stroke
                }
            }
            l.content = .text(t)
        }
        return l
    }

    /// The fills and strokes a shape or frame takes: its own from a shape,
    /// or a text's colour and stroke; nil when the style has neither.
    private func lookParts(media: Set<UUID>) -> (fills: [Fill], strokes: [Stroke])? {
        if let fills, let strokes {
            let kept = fills.filter { fill in
                guard case .image(let p) = fill.paint else { return true }
                return media.contains(p.mediaID)
            }
            return (kept.map { Fill(isEnabled: $0.isEnabled, paint: $0.paint) }, strokes.map { $0.withNewID() })
        }
        if let text {
            return ([Fill(isEnabled: text.hidesFill != true, paint: .solid(text.color))],
                    text.stroke.map { [$0.withNewID()] } ?? [])
        }
        return nil
    }

    /// The one colour a paint shows: its own, or a gradient's first stop.
    /// Nil for a picture.
    private static func color(of paint: Paint) -> RGBA? {
        switch paint {
        case .solid(let c): return c
        case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g):
            return GradientEditing.order(of: g).first.map { g.stops[$0].color }
        case .image: return nil
        }
    }
}
