import Foundation

extension Project {
    /// The colours the project uses, most used first, for the colour picker's
    /// row of document colours, as Figma shows: every solid fill, gradient
    /// stop, stroke, text colour and shadow on a layer, the colours actions
    /// change to, and the background. Colours that differ by less than a
    /// step of 255 in every channel count as one; at most `limit`.
    public func documentColors(limit: Int = 16) -> [RGBA] {
        var counts: [DocumentColorKey: (color: RGBA, count: Int, first: Int)] = [:]
        var seen = 0
        func add(_ color: RGBA) {
            let key = DocumentColorKey(color)
            if let found = counts[key] {
                counts[key] = (found.color, found.count + 1, found.first)
            } else {
                counts[key] = (color, 1, seen)
                seen += 1
            }
        }
        func add(_ paint: Paint) {
            switch paint {
            case .solid(let c): add(c)
            case .linearGradient(let g), .radialGradient(let g), .angularGradient(let g): g.stops.forEach { add($0.color) }
            case .image: break
            }
        }
        func add(_ effects: [Effect]) {
            for effect in effects {
                switch effect.kind {
                case .dropShadow(let s), .innerShadow(let s): add(s.color)
                case .layerBlur, .backgroundBlur, .glass: break
                }
            }
        }
        for layer in allLayers {
            switch layer.content {
            case .shape(let shape):
                shape.fills.forEach { add($0.paint) }
                shape.strokes.forEach { add($0.paint) }
            case .text(let text):
                add(text.color)
                if let stroke = text.stroke { add(stroke.paint) }
            case .group(let group):
                group.frame?.fills.forEach { add($0.paint) }
                group.frame?.strokes.forEach { add($0.paint) }
            case .video, .audio: break
            }
            add(layer.effects)
        }
        for action in actions {
            switch action.spec {
            case .color(let c):
                if let initial = c.initial { add(initial) }
                add(c.end)
            case .stroke(let s):
                if let initial = s.initial { add(initial.paint) }
                add(s.end.paint)
            case .shadow(let s), .innerShadow(let s):
                if let initial = s.initial { add(initial.color) }
                add(s.end.color)
            default: break
            }
        }
        if !composition.background.isTransparent { add(composition.background.color) }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.first < $1.first }
            .prefix(limit)
            .map(\.color)
    }
}

/// A colour to the nearest step of 255 in each channel, opacity included.
private struct DocumentColorKey: Hashable {
    let r, g, b, a: Int

    init(_ c: RGBA) {
        func step(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        r = step(c.r); g = step(c.g); b = step(c.b); a = step(c.a)
    }
}
