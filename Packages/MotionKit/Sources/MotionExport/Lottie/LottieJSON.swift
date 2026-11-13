import Foundation

/// A JSON value as a Lottie file holds it, written by hand rather than by
/// `JSONSerialization` so that keys keep the order Lottie's own exporter
/// uses (easier to read in a diff) and numbers are rounded to a thousandth,
/// which keeps files small: a pixel's thousandth, a colour's thousandth of
/// its range, is far below anything a player can show.
indirect enum LottieJSON: Equatable {
    case object([(String, LottieJSON)])
    case array([LottieJSON])
    case number(Double)
    case string(String)
    case bool(Bool)

    static func == (l: LottieJSON, r: LottieJSON) -> Bool {
        switch (l, r) {
        case (.object(let a), .object(let b)): a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case (.array(let a), .array(let b)): a == b
        case (.number(let a), .number(let b)): a == b
        case (.string(let a), .string(let b)): a == b
        case (.bool(let a), .bool(let b)): a == b
        default: false
        }
    }

    static func numbers(_ values: [Double]) -> LottieJSON { .array(values.map { .number($0) }) }

    /// The file's bytes.
    var data: Data {
        var out = ""
        out.reserveCapacity(1 << 16)
        write(to: &out)
        return Data(out.utf8)
    }

    func write(to out: inout String) {
        switch self {
        case .object(let pairs):
            out.append("{")
            for (i, (key, value)) in pairs.enumerated() {
                if i > 0 { out.append(",") }
                Self.writeString(key, to: &out)
                out.append(":")
                value.write(to: &out)
            }
            out.append("}")
        case .array(let items):
            out.append("[")
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(",") }
                item.write(to: &out)
            }
            out.append("]")
        case .number(let v): out.append(Self.format(v))
        case .string(let s): Self.writeString(s, to: &out)
        case .bool(let b): out.append(b ? "true" : "false")
        }
    }

    /// A number to three decimals at most, without trailing zeros. Anything
    /// not finite is written as 0, since JSON has no way to say it.
    static func format(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        let rounded = (v * 1000).rounded() / 1000
        if rounded == rounded.rounded(), abs(rounded) < 1e15 {
            let whole = Int64(rounded)
            return whole == 0 ? "0" : String(whole)
        }
        var text = String(format: "%.3f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    private static func writeString(_ s: String, to out: inout String) {
        out.append("\"")
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out.append("\\\"")
            case "\\": out.append("\\\\")
            case "\n": out.append("\\n")
            case "\r": out.append("\\r")
            case "\t": out.append("\\t")
            case _ where scalar.value < 0x20: out.append(String(format: "\\u%04x", scalar.value))
            default: out.unicodeScalars.append(scalar)
            }
        }
        out.append("\"")
    }
}
