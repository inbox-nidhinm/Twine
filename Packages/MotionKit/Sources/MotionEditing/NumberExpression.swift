import Foundation

/// What is typed into a number field, when it is more than a number: a sum
/// (`100+20`, `1920/2`, `(10+5)*2`), or a change to the number already
/// there, which starts with `+`, `*` or `/` (`+10`, `*2`, `/2`), as Figma's
/// fields take. A leading minus is a negative number, not a change; take
/// away with `+-10`. Commas are read as decimal points.
public enum NumberExpression {
    /// The value typed, worked out from `current` when it is a change to
    /// it. Nil when it is not a number or a sum, or comes to no number
    /// (a division by zero).
    public static func value(of typed: String, from current: Double) -> Double? {
        if let change = change(in: typed) { return finite(change(current)) }
        var parser = Parser(typed)
        return finite(parser.whole())
    }

    /// A change to whatever number a field holds, when what is typed starts
    /// with `+`, `*` or `/`: for several layers, each takes it from its own
    /// number. Nil for a plain number or a sum.
    public static func change(in typed: String) -> (@Sendable (Double) -> Double)? {
        let text = typed.trimmingCharacters(in: .whitespaces)
        guard let sign = text.first, "+*/".contains(sign) else { return nil }
        var parser = Parser(String(text.dropFirst()))
        guard let amount = finite(parser.whole()) else { return nil }
        switch sign {
        case "+": return { $0 + amount }
        case "*": return { $0 * amount }
        default:
            guard amount != 0 else { return nil }
            return { $0 / amount }
        }
    }

    private static func finite(_ v: Double?) -> Double? { v.flatMap { $0.isFinite ? $0 : nil } }

    /// Sums of products of numbers, brackets and minus signs, read left to
    /// right. Held to a depth, so a row of brackets cannot run the stack out.
    private struct Parser {
        private let characters: [Character]
        private var at = 0
        private var depth = 0

        init(_ text: String) {
            characters = Array(text.replacingOccurrences(of: ",", with: "."))
        }

        /// The whole text as one sum; nil if anything is left over.
        mutating func whole() -> Double? {
            guard let v = sum(), peek() == nil else { return nil }
            return v
        }

        /// The next character that is not a space. Spaces may sit round
        /// signs and brackets, never inside a number (`5 5` is not 55).
        private mutating func peek() -> Character? {
            while at < characters.count, characters[at].isWhitespace { at += 1 }
            return at < characters.count ? characters[at] : nil
        }

        private mutating func sum() -> Double? {
            guard var total = product() else { return nil }
            while let sign = peek(), sign == "+" || sign == "-" {
                at += 1
                guard let more = product() else { return nil }
                total = sign == "+" ? total + more : total - more
            }
            return total
        }

        private mutating func product() -> Double? {
            guard var total = factor() else { return nil }
            while let sign = peek(), sign == "*" || sign == "/" {
                at += 1
                guard let more = factor() else { return nil }
                total = sign == "*" ? total * more : total / more
            }
            return total
        }

        private mutating func factor() -> Double? {
            guard depth < 32 else { return nil }
            depth += 1
            defer { depth -= 1 }
            if peek() == "-" {
                at += 1
                return factor().map { -$0 }
            }
            if peek() == "(" {
                at += 1
                guard let v = sum(), peek() == ")" else { return nil }
                at += 1
                return v
            }
            let start = at
            while at < characters.count, characters[at].isASCII, characters[at].isNumber || characters[at] == "." { at += 1 }
            return at > start ? Double(String(characters[start..<at])) : nil
        }
    }
}
