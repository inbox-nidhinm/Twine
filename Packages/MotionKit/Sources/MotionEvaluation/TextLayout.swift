import Foundation
import CoreText
import CoreGraphics
import MotionModel

/// Everything that decides how a text is set, apart from the words.
public struct TextStyle: Sendable, Hashable {
    public var fontFamily: String
    /// 100 to 900.
    public var fontWeight: Int
    public var fontSize: Double
    public var alignment: TextAlignment
    public var letterSpacing: Double
    /// Baseline to baseline in pixels; nil for the font's own.
    public var lineHeight: Double?
    /// Evenly spaced digits, where the font has them, so a counter does not
    /// jiggle as it counts.
    public var tabularDigits: Bool

    public init(fontFamily: String, fontWeight: Int, fontSize: Double, alignment: TextAlignment,
                letterSpacing: Double, lineHeight: Double?, tabularDigits: Bool = false) {
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.alignment = alignment
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.tabularDigits = tabularDigits
    }

    public init(_ text: TextContent) {
        self.init(fontFamily: text.fontFamily, fontWeight: text.fontWeight, fontSize: text.fontSize,
                  alignment: text.alignment, letterSpacing: text.letterSpacing, lineHeight: text.lineHeight)
    }
}

/// One line of set text: the Core Text line, and where its baseline starts,
/// measured from the box's top-left with y running down.
public struct PositionedLine {
    public let line: CTLine
    public let origin: CGPoint
}

/// Sets text the same way for measuring and for drawing, with Core Text, so
/// the box a layer gets is exactly the box its text is drawn in.
///
/// Lines are placed by hand rather than by a frame: each is one line height
/// tall, with the glyphs centred in it (half the spare height above, half
/// below), which is how Figma places text and what makes a line height
/// change look even.
public enum TextLayout {
    /// The family the system font goes by here. SF Pro is only installed as a
    /// named family where someone has added it, so this name always means
    /// the system face.
    public static let systemFamily = "SF Pro"

    /// Whether `family` can be drawn as itself, rather than in the fallback.
    public static func isInstalled(_ family: String) -> Bool {
        if isSystem(family) { return true }
        return installedFamilies.contains { $0.caseInsensitiveCompare(family) == .orderedSame }
    }

    public static var installedFamilies: [String] {
        (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
    }

    private static func isSystem(_ family: String) -> Bool {
        let f = family.trimmingCharacters(in: .whitespaces).lowercased()
        return f.isEmpty || f == "sf pro" || f == "system" || f == "sf pro text" || f == "sf pro display"
    }

    /// The font for a style. A family that is not installed falls back to
    /// the system font at the same weight and size.
    public static func font(_ style: TextStyle) -> CTFont {
        let size = CGFloat(max(style.fontSize, 1))
        let traits: [CFString: Any] = [kCTFontWeightTrait: weightTrait(style.fontWeight)]
        var attributes: [CFString: Any] = [kCTFontTraitsAttribute: traits]
        if style.tabularDigits {
            attributes[kCTFontFeatureSettingsAttribute] = [[
                kCTFontOpenTypeFeatureTag: "tnum", kCTFontOpenTypeFeatureValue: 1,
            ]]
        }
        let base: CTFont
        if !isSystem(style.fontFamily), isInstalled(style.fontFamily) {
            attributes[kCTFontFamilyNameAttribute] = style.fontFamily
            base = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes as CFDictionary), size, nil)
        } else {
            let system = CTFontCreateUIFontForLanguage(.system, size, nil) ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(system), attributes as CFDictionary)
            base = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        }
        return base
    }

    /// CSS's 100 to 900 on Core Text's scale, where 0 is regular.
    static func weightTrait(_ weight: Int) -> Double {
        let table: [(Int, Double)] = [(100, -0.8), (200, -0.6), (300, -0.4), (400, 0), (500, 0.23),
                                      (600, 0.3), (700, 0.4), (800, 0.56), (900, 0.62)]
        let w = min(max(weight, 100), 900)
        for (lo, hi) in zip(table, table.dropFirst()) where w <= hi.0 {
            let f = Double(w - lo.0) / Double(hi.0 - lo.0)
            return lo.1 + (hi.1 - lo.1) * f
        }
        return 0.62
    }

    /// The font's own line height: its ascent, descent and line gap.
    public static func naturalLineHeight(_ style: TextStyle) -> Double {
        let f = font(style)
        return Double(CTFontGetAscent(f) + CTFontGetDescent(f) + CTFontGetLeading(f))
    }

    /// The box `text` needs: as wide as its longest line, or `width` when it
    /// wraps in a fixed width, and one line height per line.
    public static func size(of text: String, style: TextStyle, width: Double?) -> Size2 {
        layout(text, style: style, width: width).size
    }

    /// The lines of `text`, placed in its box.
    public static func layout(_ text: String, style: TextStyle, width: Double?) -> (lines: [PositionedLine], size: Size2) {
        let f = font(style)
        let ascent = Double(CTFontGetAscent(f)), descent = Double(CTFontGetDescent(f))
        let lineHeight = style.lineHeight ?? naturalLineHeight(style)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: f,
            kCTKernAttributeName: style.letterSpacing,
            kCTForegroundColorFromContextAttributeName: true,
        ]

        // Each paragraph broken into lines: wrapped to the width when there
        // is one, otherwise one line each.
        var set: [(line: CTLine, lastInParagraph: Bool)] = []
        for paragraph in text.components(separatedBy: "\n") {
            let string = CFAttributedStringCreate(nil, paragraph as CFString, attributes as CFDictionary)!
            let length = CFAttributedStringGetLength(string)
            guard let width, length > 0 else {
                set.append((CTLineCreateWithAttributedString(string), true))
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(string)
            var start = 0
            while start < length {
                let count = max(CTTypesetterSuggestLineBreak(typesetter, start, max(width, 1)), 1)
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                start += count
                set.append((line, start >= length))
            }
        }

        func measure(_ line: CTLine) -> Double {
            let full = CTLineGetTypographicBounds(line, nil, nil, nil)
            var w = full - CTLineGetTrailingWhitespaceWidth(line)
            // Letter spacing follows every letter, the last one too; the box
            // stops at the last letter.
            if CTLineGetGlyphCount(line) > 0 { w -= style.letterSpacing }
            return max(w, 0)
        }

        let boxWidth = width ?? (set.map { measure($0.line) }.max() ?? 0)
        var lines: [PositionedLine] = []
        for (index, entry) in set.enumerated() {
            var line = entry.line
            var lineWidth = measure(line)
            if style.alignment == .justified, width != nil, !entry.lastInParagraph,
               let justified = CTLineCreateJustifiedLine(line, 1, boxWidth) {
                line = justified
                lineWidth = boxWidth
            }
            let x: Double
            switch style.alignment {
            case .left, .justified: x = 0
            case .center: x = (boxWidth - lineWidth) / 2
            case .right: x = boxWidth - lineWidth
            }
            let baseline = Double(index) * lineHeight + (lineHeight - (ascent + descent)) / 2 + ascent
            lines.append(PositionedLine(line: line, origin: CGPoint(x: x, y: baseline)))
        }
        return (lines, Size2(ceil(boxWidth), Double(max(set.count, 1)) * lineHeight))
    }

    /// Where the anchor goes when a text box changes size, so the text grows
    /// the way its alignment reads: left-aligned text grows to the right,
    /// centred text both ways, right-aligned text to the left, and every text
    /// downwards.
    public static func anchor(_ anchor: Vec2, from old: Size2, to new: Size2, alignment: TextAlignment) -> Vec2 {
        let x: Double
        switch alignment {
        case .left, .justified: x = anchor.x
        case .center: x = old.width > 0 ? anchor.x * new.width / old.width : new.width / 2
        case .right: x = anchor.x + (new.width - old.width)
        }
        return Vec2(x, anchor.y)
    }
}
