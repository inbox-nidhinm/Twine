import Foundation

/// How a number is written in a text, found by reading it: what comes before
/// and after it, its decimals, its thousands separator and its zero padding.
/// A Counter writes every number it counts through the same way, so
/// `$1,200.50` counts in dollars and cents and `007` keeps its zeros.
public struct NumberFormat: Sendable, Equatable {
    public var prefix: String
    public var suffix: String
    public var decimals: Int
    /// Nil when the number is written without one.
    public var groupingSeparator: Character?
    public var decimalSeparator: Character
    /// At least this many digits before the decimal point, padded with zeros.
    public var minimumIntegerDigits: Int

    public init(prefix: String = "", suffix: String = "", decimals: Int = 0, groupingSeparator: Character? = nil,
                decimalSeparator: Character = ".", minimumIntegerDigits: Int = 1) {
        self.prefix = prefix
        self.suffix = suffix
        self.decimals = decimals
        self.groupingSeparator = groupingSeparator
        self.decimalSeparator = decimalSeparator
        self.minimumIntegerDigits = minimumIntegerDigits
    }

    /// The first number in `text` and how it is written, or nil if there is
    /// none. One separator followed by exactly three digits reads as a
    /// thousands separator (`1,000`); followed by any other count, as a
    /// decimal point (`3.5`). With both kinds, the last one is the decimal
    /// point, which reads `1.200,50` the European way.
    public static func read(_ text: String) -> (format: NumberFormat, value: Double)? {
        let chars = Array(text)
        guard let firstDigit = chars.firstIndex(where: \.isNumber) else { return nil }
        var start = firstDigit
        if start > 0, chars[start - 1] == "-" || chars[start - 1] == "−" { start -= 1 }
        var end = firstDigit
        // Digits, and separators with a digit straight after them.
        while end < chars.count {
            if chars[end].isNumber {
                end += 1
            } else if (chars[end] == "," || chars[end] == "."), end + 1 < chars.count, chars[end + 1].isNumber {
                end += 1
            } else {
                break
            }
        }
        let body = Array(chars[firstDigit..<end])
        let negative = start < firstDigit
        let separators = body.filter { $0 == "," || $0 == "." }

        var grouping: Character?
        var decimal: Character = "."
        var decimals = 0
        if let last = separators.last {
            let kinds = Set(separators)
            let lastIndex = body.lastIndex(of: last)!
            let digitsAfter = body.count - lastIndex - 1
            if kinds.count > 1 {
                decimal = last
                grouping = kinds.first { $0 != last }
                decimals = digitsAfter
            } else if separators.count > 1 || digitsAfter == 3 {
                grouping = last
                decimal = last == "," ? "." : ","
            } else {
                decimal = last
                decimals = digitsAfter
            }
        }
        var digits = ""
        for c in body {
            if c.isNumber { digits.append(c) } else if c == decimal { digits.append(".") }
        }
        guard var value = Double(digits) else { return nil }
        if negative { value = -value }
        let integerPart = body.prefix { $0 != decimal || decimals == 0 }.filter(\.isNumber)
        let padded = integerPart.count > 1 && integerPart.first == "0" ? integerPart.count : 1
        let format = NumberFormat(prefix: String(chars[0..<start]), suffix: String(chars[end...]), decimals: decimals,
                                  groupingSeparator: grouping, decimalSeparator: decimal,
                                  minimumIntegerDigits: padded)
        return (format, value)
    }

    /// `value` written this way.
    public func text(for value: Double) -> String {
        let rounded = (value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals))
        let negative = rounded < 0 && abs(rounded) > 0
        let magnitude = abs(rounded)
        let fixed = String(format: "%.\(decimals)f", magnitude)
        let parts = fixed.split(separator: ".", omittingEmptySubsequences: false)
        var integer = String(parts[0])
        if integer.count < minimumIntegerDigits {
            integer = String(repeating: "0", count: minimumIntegerDigits - integer.count) + integer
        }
        if let groupingSeparator {
            var grouped = ""
            for (i, c) in integer.reversed().enumerated() {
                if i > 0 && i % 3 == 0 { grouped.append(groupingSeparator) }
                grouped.append(c)
            }
            integer = String(grouped.reversed())
        }
        var number = integer
        if decimals > 0, parts.count > 1 { number += String(decimalSeparator) + parts[1] }
        return prefix + (negative ? "-" : "") + number + suffix
    }

    /// Places of decimals `value` needs, up to four.
    static func decimals(of value: Double) -> Int {
        for places in 0...4 {
            let scaled = value * pow(10, Double(places))
            if abs(scaled - scaled.rounded()) < 1e-6 { return places }
        }
        return 4
    }
}
