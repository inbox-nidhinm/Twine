import Foundation
import MotionModel

/// An element's style properties as SVG works them out: presentation
/// attributes, then CSS class rules from `<style>`, then its `style`
/// attribute, each overriding the last. Inherited properties pass to
/// children; the rest (opacity, clipping, masks, filters, blending) belong to
/// the element alone.
struct SVGStyle {
    /// Properties that pass from an element to its children.
    static let inherited: Set<String> = [
        "fill", "fill-opacity", "fill-rule", "stroke", "stroke-width", "stroke-opacity", "stroke-linecap",
        "stroke-linejoin", "stroke-dasharray", "stroke-dashoffset", "color", "visibility", "clip-rule",
        "font-family", "font-size", "font-weight", "font-style", "text-anchor", "letter-spacing",
    ]

    private(set) var values: [String: String]

    init(values: [String: String] = [:]) { self.values = values }

    subscript(_ name: String) -> String? { values[name] }

    /// The style of `element`, whose parent's is `parent`.
    static func of(_ element: XMLElement, parent: SVGStyle, sheet: SVGStyleSheet) -> SVGStyle {
        var values = parent.values.filter { inherited.contains($0.key) }
        for attribute in element.attributes ?? [] {
            guard let name = attribute.name, let value = attribute.stringValue else { continue }
            if name != "style", name != "class", name != "transform" { values[name] = value.trimmed }
        }
        for name in (element.attribute(forName: "class")?.stringValue ?? "").split(separator: " ") {
            for (key, value) in sheet.rules[String(name)] ?? [:] { values[key] = value }
        }
        if let style = element.attribute(forName: "style")?.stringValue {
            for (key, value) in declarations(style) { values[key] = value }
        }
        // `inherit` takes the parent's value.
        for (key, value) in values where value == "inherit" { values[key] = parent.values[key] }
        return SVGStyle(values: values)
    }

    /// `a: b; c: d` as pairs.
    static func declarations(_ text: String) -> [(String, String)] {
        text.split(separator: ";").compactMap { part in
            let pieces = part.split(separator: ":", maxSplits: 1)
            guard pieces.count == 2 else { return nil }
            return (pieces[0].trimmed.lowercased(), pieces[1].trimmed.replacingOccurrences(of: "!important", with: "").trimmed)
        }
    }

    func number(_ name: String, default fallback: Double) -> Double {
        values[name].flatMap(SVGNumber.parse) ?? fallback
    }

    /// 0 to 1, from a number or a percentage.
    func fraction(_ name: String) -> Double {
        guard let text = values[name] else { return 1 }
        if text.hasSuffix("%"), let v = Double(text.dropLast()) { return min(max(v / 100, 0), 1) }
        return min(max(Double(text) ?? 1, 0), 1)
    }
}

/// Class rules from `<style>` elements, as Illustrator and other tools
/// write them: `.cls-1 { fill: #333; }`, several classes to a rule allowed.
/// Other selectors are left alone.
struct SVGStyleSheet {
    var rules: [String: [String: String]] = [:]

    init(_ document: XMLDocument) {
        let styles = (try? document.nodes(forXPath: "//*[local-name()='style']")) ?? []
        for node in styles {
            let css = (node.stringValue ?? "").replacingOccurrences(of: "/\\*[\\s\\S]*?\\*/", with: "", options: .regularExpression)
            for block in css.split(separator: "}") {
                let parts = block.split(separator: "{", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let body = SVGStyle.declarations(String(parts[1]))
                for selector in parts[0].split(separator: ",") {
                    let s = selector.trimmed
                    guard s.hasPrefix("."), !s.dropFirst().contains(where: { " .#:[>".contains($0) }) else { continue }
                    var rule = rules[String(s.dropFirst())] ?? [:]
                    for (key, value) in body { rule[key] = value }
                    rules[String(s.dropFirst())] = rule
                }
            }
        }
    }
}

enum SVGNumber {
    /// A length in user units: plain, or in px or pt. Percentages and other
    /// units read as their number, which is right for the plain files design
    /// tools write.
    static func parse(_ text: String) -> Double? {
        var t = text.trimmed
        for unit in ["px", "pt", "em"] where t.hasSuffix(unit) {
            let value = Double(t.dropLast(unit.count))
            return unit == "pt" ? value.map { $0 * 4 / 3 } : unit == "em" ? value.map { $0 * 16 } : value
        }
        if t.hasSuffix("%") { t.removeLast() }
        return Double(t)
    }

    /// A list of numbers split by spaces or commas.
    static func list(_ text: String) -> [Double] {
        var scanner = NumberScanner(text)
        var out: [Double] = []
        while let v = scanner.number() { out.append(v) }
        return out
    }
}

enum SVGColor {
    /// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`,
    /// `hsla()`, a CSS colour name or `transparent`. Nil for anything else,
    /// such as `none` or a `url(...)`.
    static func parse(_ text: String) -> RGBA? {
        let t = text.trimmed.lowercased()
        if t.hasPrefix("#") {
            var hex = String(t.dropFirst())
            if hex.count == 3 || hex.count == 4 { hex = hex.map { "\($0)\($0)" }.joined() }
            return RGBA(hex: hex)
        }
        if t.hasPrefix("rgb") || t.hasPrefix("hsl"), let open = t.firstIndex(of: "("), let close = t.lastIndex(of: ")") {
            let inner = t[t.index(after: open)..<close].replacingOccurrences(of: "/", with: " ")
            let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " }).map(String.init)
            guard parts.count >= 3 else { return nil }
            func channel(_ s: String, max: Double) -> Double {
                s.hasSuffix("%") ? (Double(s.dropLast()) ?? 0) / 100 : (Double(s) ?? 0) / max
            }
            let alpha = parts.count > 3 ? channel(parts[3], max: 1) : 1
            if t.hasPrefix("rgb") {
                return RGBA(channel(parts[0], max: 255), channel(parts[1], max: 255), channel(parts[2], max: 255), alpha)
            }
            let h = (Double(parts[0].replacingOccurrences(of: "deg", with: "")) ?? 0) / 360
            return hsl(h, channel(parts[1], max: 100), channel(parts[2], max: 100), alpha)
        }
        if t == "transparent" { return .clear }
        return named[t].flatMap { RGBA(hex: $0) }
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double, _ a: Double) -> RGBA {
        func f(_ n: Double) -> Double {
            let k = (n + h * 12).truncatingRemainder(dividingBy: 12)
            return l - s * min(l, 1 - l) * max(-1, min(k - 3, 9 - k, 1))
        }
        return RGBA(f(0), f(8), f(4), a)
    }

    /// The CSS colour names.
    static let named: [String: String] = [
        "aliceblue": "F0F8FF", "antiquewhite": "FAEBD7", "aqua": "00FFFF", "aquamarine": "7FFFD4", "azure": "F0FFFF",
        "beige": "F5F5DC", "bisque": "FFE4C4", "black": "000000", "blanchedalmond": "FFEBCD", "blue": "0000FF",
        "blueviolet": "8A2BE2", "brown": "A52A2A", "burlywood": "DEB887", "cadetblue": "5F9EA0", "chartreuse": "7FFF00",
        "chocolate": "D2691E", "coral": "FF7F50", "cornflowerblue": "6495ED", "cornsilk": "FFF8DC", "crimson": "DC143C",
        "cyan": "00FFFF", "darkblue": "00008B", "darkcyan": "008B8B", "darkgoldenrod": "B8860B", "darkgray": "A9A9A9",
        "darkgreen": "006400", "darkgrey": "A9A9A9", "darkkhaki": "BDB76B", "darkmagenta": "8B008B",
        "darkolivegreen": "556B2F", "darkorange": "FF8C00", "darkorchid": "9932CC", "darkred": "8B0000",
        "darksalmon": "E9967A", "darkseagreen": "8FBC8F", "darkslateblue": "483D8B", "darkslategray": "2F4F4F",
        "darkslategrey": "2F4F4F", "darkturquoise": "00CED1", "darkviolet": "9400D3", "deeppink": "FF1493",
        "deepskyblue": "00BFFF", "dimgray": "696969", "dimgrey": "696969", "dodgerblue": "1E90FF", "firebrick": "B22222",
        "floralwhite": "FFFAF0", "forestgreen": "228B22", "fuchsia": "FF00FF", "gainsboro": "DCDCDC", "ghostwhite": "F8F8FF",
        "gold": "FFD700", "goldenrod": "DAA520", "gray": "808080", "green": "008000", "greenyellow": "ADFF2F",
        "grey": "808080", "honeydew": "F0FFF0", "hotpink": "FF69B4", "indianred": "CD5C5C", "indigo": "4B0082",
        "ivory": "FFFFF0", "khaki": "F0E68C", "lavender": "E6E6FA", "lavenderblush": "FFF0F5", "lawngreen": "7CFC00",
        "lemonchiffon": "FFFACD", "lightblue": "ADD8E6", "lightcoral": "F08080", "lightcyan": "E0FFFF",
        "lightgoldenrodyellow": "FAFAD2", "lightgray": "D3D3D3", "lightgreen": "90EE90", "lightgrey": "D3D3D3",
        "lightpink": "FFB6C1", "lightsalmon": "FFA07A", "lightseagreen": "20B2AA", "lightskyblue": "87CEFA",
        "lightslategray": "778899", "lightslategrey": "778899", "lightsteelblue": "B0C4DE", "lightyellow": "FFFFE0",
        "lime": "00FF00", "limegreen": "32CD32", "linen": "FAF0E6", "magenta": "FF00FF", "maroon": "800000",
        "mediumaquamarine": "66CDAA", "mediumblue": "0000CD", "mediumorchid": "BA55D3", "mediumpurple": "9370DB",
        "mediumseagreen": "3CB371", "mediumslateblue": "7B68EE", "mediumspringgreen": "00FA9A",
        "mediumturquoise": "48D1CC", "mediumvioletred": "C71585", "midnightblue": "191970", "mintcream": "F5FFFA",
        "mistyrose": "FFE4E1", "moccasin": "FFE4B5", "navajowhite": "FFDEAD", "navy": "000080", "oldlace": "FDF5E6",
        "olive": "808000", "olivedrab": "6B8E23", "orange": "FFA500", "orangered": "FF4500", "orchid": "DA70D6",
        "palegoldenrod": "EEE8AA", "palegreen": "98FB98", "paleturquoise": "AFEEEE", "palevioletred": "DB7093",
        "papayawhip": "FFEFD5", "peachpuff": "FFDAB9", "peru": "CD853F", "pink": "FFC0CB", "plum": "DDA0DD",
        "powderblue": "B0E0E6", "purple": "800080", "rebeccapurple": "663399", "red": "FF0000", "rosybrown": "BC8F8F",
        "royalblue": "4169E1", "saddlebrown": "8B4513", "salmon": "FA8072", "sandybrown": "F4A460", "seagreen": "2E8B57",
        "seashell": "FFF5EE", "sienna": "A0522D", "silver": "C0C0C0", "skyblue": "87CEEB", "slateblue": "6A5ACD",
        "slategray": "708090", "slategrey": "708090", "snow": "FFFAFA", "springgreen": "00FF7F", "steelblue": "4682B4",
        "tan": "D2B48C", "teal": "008080", "thistle": "D8BFD8", "tomato": "FF6347", "turquoise": "40E0D0",
        "violet": "EE82EE", "wheat": "F5DEB3", "white": "FFFFFF", "whitesmoke": "F5F5F5", "yellow": "FFFF00",
        "yellowgreen": "9ACD32",
    ]
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
