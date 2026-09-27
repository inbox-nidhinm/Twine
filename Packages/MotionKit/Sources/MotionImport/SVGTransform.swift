import Foundation
import MotionModel
import MotionEvaluation

enum SVGTransform {
    /// A `transform` attribute: any list of `matrix`, `translate`, `scale`,
    /// `rotate`, `skewX` and `skewY`, the first applying outermost, as SVG
    /// reads them.
    static func parse(_ text: String?) -> Affine {
        guard let text, !text.isEmpty else { return .identity }
        var result = Affine.identity
        let pattern = try! NSRegularExpression(pattern: "(matrix|translate|scale|rotate|skewX|skewY)\\s*\\(([^)]*)\\)")
        let ns = text as NSString
        var steps: [Affine] = []
        for match in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            let v = SVGNumber.list(ns.substring(with: match.range(at: 2)))
            func at(_ i: Int, _ fallback: Double = 0) -> Double { i < v.count ? v[i] : fallback }
            switch name {
            case "matrix" where v.count == 6:
                steps.append(Affine(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5]))
            case "translate":
                steps.append(.translation(Vec2(at(0), at(1))))
            case "scale":
                steps.append(.scale(Vec2(at(0, 1), v.count > 1 ? v[1] : at(0, 1))))
            case "rotate":
                let turn = Affine.rotation(degrees: at(0))
                if v.count >= 3 {
                    let c = Vec2(v[1], v[2])
                    steps.append(Affine.translation(Vec2(-c.x, -c.y)).then(turn).then(.translation(c)))
                } else {
                    steps.append(turn)
                }
            case "skewX":
                steps.append(Affine(a: 1, b: 0, c: tan(at(0) * .pi / 180), d: 1, tx: 0, ty: 0))
            case "skewY":
                steps.append(Affine(a: 1, b: tan(at(0) * .pi / 180), c: 0, d: 1, tx: 0, ty: 0))
            default:
                continue
            }
        }
        // `translate(a) rotate(b)` rotates first, then translates.
        for step in steps.reversed() { result = result.then(step) }
        return result
    }

    /// A transform that only moves, turns and scales each way, as a layer's
    /// own can: its turn in degrees and its two scales. Nil for one that
    /// skews or mirrors, which a layer cannot show, so its shape is drawn
    /// through it instead.
    static func decompose(_ t: Affine) -> (rotation: Double, scale: Vec2)? {
        let sx = hypot(t.a, t.b), sy = hypot(t.c, t.d)
        guard sx > 1e-9, sy > 1e-9, t.determinant > 0, abs(t.a * t.c + t.b * t.d) < 1e-6 * sx * sy else { return nil }
        return (atan2(t.b, t.a) * 180 / .pi, Vec2(sx, sy))
    }
}

/// Figma's effects, read back out of the filters its SVG export writes.
/// Figma names each effect's last step (`effect1_dropShadow_12_34`), so the
/// steps between one name and the next are one effect: an offset, a blur, a
/// spread (`feMorphology`) and a colour (the last colour matrix). Anything
/// else in a filter is left out.
enum SVGFilters {
    static func effects(_ filter: XMLElement) -> [EffectKind] {
        var effects: [EffectKind] = []
        var offset = Vec2.zero, deviation = 0.0, spread = 0.0, color = RGBA(0, 0, 0, 0.25)
        for step in filter.children?.compactMap({ $0 as? XMLElement }) ?? [] {
            let name = step.localName ?? ""
            func attr(_ n: String) -> String? { step.attribute(forName: n)?.stringValue }
            switch name {
            case "feOffset":
                offset = Vec2(Double(attr("dx") ?? "0") ?? 0, Double(attr("dy") ?? "0") ?? 0)
            case "feGaussianBlur":
                deviation = SVGNumber.list(attr("stdDeviation") ?? "0").first ?? 0
            case "feMorphology":
                let r = SVGNumber.list(attr("radius") ?? "0").first ?? 0
                spread = attr("operator") == "erode" ? -r : r
            case "feColorMatrix":
                let v = SVGNumber.list(attr("values") ?? "")
                // Figma's first matrix only takes the shape's alpha.
                if attr("result") != "hardAlpha", attr("in") != "SourceAlpha", v.count == 20 {
                    color = RGBA(v[4], v[9], v[14], v[18])
                }
            default:
                break
            }
            // Figma names more than the last step of a shadow (its spread,
            // too), so a shadow ends at the blend that carries its name.
            let result = (name == "feBlend" || name == "feGaussianBlur") ? attr("result") ?? "" : ""
            let shadow = DropShadow(color: RGBA(color.r, color.g, color.b), offset: offset, blur: deviation * 2,
                                    opacity: color.a, spread: spread)
            if name == "feBlend", result.contains("dropShadow") {
                effects.append(.dropShadow(shadow))
            } else if name == "feBlend", result.contains("innerShadow") {
                var inner = shadow
                inner.spread = -spread
                effects.append(.innerShadow(inner))
            } else if result.contains("foregroundBlur") || result.contains("layerBlur") {
                effects.append(.layerBlur(LayerBlur(radius: deviation * 2)))
            } else {
                continue
            }
            offset = .zero
            deviation = 0
            spread = 0
            color = RGBA(0, 0, 0, 0.25)
        }
        return effects
    }
}
