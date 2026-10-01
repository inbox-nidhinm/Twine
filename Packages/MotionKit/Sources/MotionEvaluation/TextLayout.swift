import Foundation
import CoreText
import Synchronization
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
    /// The characters it shows, in UTF-16 units of the whole text, without
    /// the line break that may end it.
    public let range: NSRange
    /// Where its paragraph starts in the whole text: the line's own string
    /// indices count from there.
    public let paragraphStart: Int
    /// Its box, a line height tall, from the top of the text.
    public let top: Double
    public let height: Double
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
        _ = watchingFonts
        let name = family.lowercased()
        return installed.withLock { known in
            if let known { return known.contains(name) }
            let families = Set(installedFamilies.map { $0.lowercased() })
            known = families
            return families.contains(name)
        }
    }

    /// The installed families, lowercased, kept until fonts are added or
    /// removed. Asking Core Text for the list takes about a tenth of a second
    /// on a Mac with many fonts, and it was asked for each new text style:
    /// opening a project with 16 styles spent 1.6 s on it.
    private static let installed = Mutex<Set<String>?>(nil)

    /// Fonts installed or removed while Twine runs are found again, and
    /// text is set afresh in them.
    private static let watchingFonts: Void = {
        CFNotificationCenterAddObserver(CFNotificationCenterGetLocalCenter(), nil, { _, _, _, _, _ in
            TextLayout.installed.withLock { $0 = nil }
            TextLayout.fonts.withLock { $0.removeAll() }
            TextLayout.layouts.withLock { $0 = Generations() }
        }, kCTFontManagerRegisteredFontsChangedNotification, nil, .deliverImmediately)
    }()

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
        let key = FontKey(style)
        if let known = fonts.withLock({ $0[key] }) { return known.font }
        let made = makeFont(style)
        fonts.withLock { cache in
            if cache.count > 64 { cache.removeAll() }
            cache[key] = Unchecked(font: made)
        }
        return made
    }

    // MARK: Caches
    //
    // Setting text is the dearest part of working out a frame, and the same
    // words in the same style come round on every frame and every edit. Core
    // Text's fonts and lines never change once made, so they are shared
    // between the canvas and a background export, behind a lock.

    private struct FontKey: Hashable {
        let family: String, weight: Int, size: Double, tabular: Bool
        init(_ s: TextStyle) { (family, weight, size, tabular) = (s.fontFamily, s.fontWeight, s.fontSize, s.tabularDigits) }
    }

    private struct Unchecked: @unchecked Sendable { let font: CTFont }

    private struct LayoutKey: Hashable {
        let text: String, style: TextStyle, width: Double?
    }

    private struct LaidOut: @unchecked Sendable {
        let lines: [PositionedLine]
        let size: Size2
    }

    private static let fonts = Mutex<[FontKey: Unchecked]>([:])
    /// Two generations: when the newer fills, it becomes the older and a
    /// fresh one starts, and anything found in the older is carried into the
    /// newer. So texts in use stay laid out while a Counter or a spacing
    /// action makes a new entry every frame; emptying the whole cache when
    /// full laid every text in the scene out again every eight seconds.
    private struct Generations: Sendable {
        var current: [LayoutKey: LaidOut] = [:]
        var previous: [LayoutKey: LaidOut] = [:]

        mutating func insert(_ value: LaidOut, for key: LayoutKey) {
            if current.count >= layoutLimit {
                previous = current
                current = [:]
            }
            current[key] = value
        }
    }

    private static let layouts = Mutex(Generations())
    /// Enough for every text in a large scene in each generation. At 512, a
    /// project with 630 texts (a Figma import of a few dozen screens) never
    /// found them all, and laid most out again on every edit and frame.
    private static let layoutLimit = 4096

    private static func makeFont(_ style: TextStyle) -> CTFont {
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
        let key = LayoutKey(text: text, style: style, width: width)
        let known = layouts.withLock { g -> LaidOut? in
            if let hit = g.current[key] { return hit }
            guard let old = g.previous[key] else { return nil }
            g.insert(old, for: key)
            return old
        }
        if let known { return (known.lines, known.size) }
        let made = setLines(text, style: style, width: width)
        layouts.withLock { $0.insert(LaidOut(lines: made.lines, size: made.size), for: key) }
        return made
    }

    private static func setLines(_ text: String, style: TextStyle, width: Double?) -> (lines: [PositionedLine], size: Size2) {
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
        var set: [(line: CTLine, lastInParagraph: Bool, range: NSRange, paragraphStart: Int)] = []
        var paragraphStart = 0
        for paragraph in text.components(separatedBy: "\n") {
            let string = CFAttributedStringCreate(nil, paragraph as CFString, attributes as CFDictionary)!
            let length = CFAttributedStringGetLength(string)
            defer { paragraphStart += length + 1 }
            guard let width, length > 0 else {
                set.append((CTLineCreateWithAttributedString(string), true, NSRange(location: paragraphStart, length: length),
                            paragraphStart))
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(string)
            var start = 0
            while start < length {
                let count = max(CTTypesetterSuggestLineBreak(typesetter, start, max(width, 1)), 1)
                let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                set.append((line, start + count >= length, NSRange(location: paragraphStart + start, length: count),
                            paragraphStart))
                start += count
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
            let top = Double(index) * lineHeight
            let baseline = top + (lineHeight - (ascent + descent)) / 2 + ascent
            lines.append(PositionedLine(line: line, origin: CGPoint(x: x, y: baseline), range: entry.range,
                                        paragraphStart: entry.paragraphStart, top: top, height: lineHeight))
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
