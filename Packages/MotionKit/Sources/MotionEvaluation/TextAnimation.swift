import Foundation
import CoreText
import MotionModel

/// A preset set to move a text's letters, words or lines one by one, ready
/// to play: the bar, and its recipe on a stand-in layer that stands for one
/// letter at rest (at the origin, full size, unturned, opaque), so each
/// letter's state is what the preset does to that stand-in.
struct TextPreset: Sendable {
    let action: Action
    let settings: PresetAction
    let tracks: ActionTracks

    init(_ action: Action, _ settings: PresetAction) {
        self.action = action
        self.settings = settings
        var own = settings
        own.unit = nil
        var played = action
        played.targetLayerID = TextAnimation.stand.id
        played.start = 0
        played.spec = .preset(own)
        tracks = ActionTracks([played])
    }
}

/// How a text preset moves each letter, word or line of a text at a moment.
///
/// The bar is the whole animation: the first letter starts with it and the
/// last ends with it, each starting `delay` after the one before (in the
/// preset's order) and running the preset in what is left. A delay too long
/// for the text is shortened so every letter still takes a quarter of the
/// bar.
public struct TextAnimation: Sendable {
    public let unit: TextUnit
    let preset: TextPreset

    init(_ preset: TextPreset) {
        self.preset = preset
        unit = preset.settings.unit ?? .letters
    }

    /// One letter at rest, the stand-in every letter's state is measured on.
    static let stand: Layer = {
        var layer = Layer(id: UUID(uuidString: "7E47A9B1-0000-4000-8000-000000000001")!, name: "Letter",
                          content: .shape(ShapeContent(geometry: .rectangle(cornerRadii: .zero), fills: [])),
                          size: Size2(1, 1), position: .zero)
        layer.transform.anchor = .zero
        return layer
    }()

    /// A letter's state when nothing moves it.
    public static let rest = LayerState(design: stand)

    /// Each of `count` letters' states at `time`, in reading order: where it
    /// has moved from its place (`position`), and its scale, turn, tilt,
    /// opacity, blur and reveal, about its own centre.
    public func states(count: Int, at time: Double) -> [LayerState] {
        guard count > 0 else { return [] }
        let action = preset.action
        let ranks = Self.ranks(count, order: preset.settings.order ?? .forward, seed: action.id)
        let last = ranks.max() ?? 0
        var delay = max(preset.settings.delay ?? unit.delay, 0)
        var each = action.duration - last * delay
        if last > 0, each < action.duration * 0.25 {
            each = action.duration * 0.25
            delay = (action.duration - each) / last
        }
        // Each letter runs the whole recipe in its own share of the bar.
        let stretch = each > 0 ? action.duration / each : 0
        return ranks.map { rank in
            let local = time - action.start - rank * delay
            let t = each > 0 ? local * stretch : (local >= 0 ? action.duration : -1)
            return preset.tracks.state(of: Self.stand, at: t)
        }
    }

    /// When each of `count` letters starts, in steps of the delay.
    public static func ranks(_ count: Int, order: TextOrder, seed: UUID) -> [Double] {
        let middle = Double(count - 1) / 2
        switch order {
        case .forward: return (0..<count).map(Double.init)
        case .backward: return (0..<count).map { Double(count - 1 - $0) }
        case .center: return (0..<count).map { abs(Double($0) - middle) }
        case .edges: return (0..<count).map { middle - abs(Double($0) - middle) }
        case .random:
            // The same shuffle for the same bar every time it plays.
            var generator = SeededGenerator(seed)
            var order = Array(0..<count)
            order.shuffle(using: &generator)
            var ranks = [Double](repeating: 0, count: count)
            for (rank, index) in order.enumerated() { ranks[index] = Double(rank) }
            return ranks
        }
    }
}

/// SplitMix64, seeded from an id's bytes.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64

    init(_ id: UUID) {
        let b = id.uuid
        state = [b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7].reduce(0) { $0 << 8 | UInt64($1) }
            ^ [b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15].reduce(0) { $0 << 8 | UInt64($1) }
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// One letter, word or line of a set text: its characters, in UTF-16 units
/// of the whole text, and its box in the text's own space (a line height
/// tall, from the first letter's left to the last one's right).
public struct TextSpan: Sendable, Equatable {
    public var range: NSRange
    public var box: Box
}

public enum TextSpans {
    /// The letters, words or lines of `text` as `TextLayout` sets it, in
    /// reading order. Spaces and line breaks are no letter and belong to no
    /// word.
    public static func spans(_ unit: TextUnit, of text: String, style: TextStyle, width: Double?) -> [TextSpan] {
        let lines = TextLayout.layout(text, style: style, width: width).lines
        let string = text as NSString
        func isGap(_ i: Int) -> Bool {
            guard let scalar = UnicodeScalar(string.character(at: i)) else { return false }
            return CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        var spans: [TextSpan] = []
        for line in lines {
            let start = line.range.location, end = line.range.location + line.range.length
            func span(_ lo: Int, _ hi: Int) {
                let a = Double(line.origin.x) + Double(CTLineGetOffsetForStringIndex(line.line, lo - line.paragraphStart, nil))
                let b = Double(line.origin.x) + Double(CTLineGetOffsetForStringIndex(line.line, hi - line.paragraphStart, nil))
                spans.append(TextSpan(range: NSRange(location: lo, length: hi - lo),
                                      box: Box(origin: Vec2(min(a, b), line.top), size: Size2(abs(b - a), line.height))))
            }
            switch unit {
            case .letters:
                var i = start
                while i < end {
                    let r = string.rangeOfComposedCharacterSequence(at: i)
                    if !isGap(i) { span(r.location, min(r.location + r.length, end)) }
                    i = r.location + max(r.length, 1)
                }
            case .words:
                var i = start
                while i < end {
                    while i < end, isGap(i) { i += 1 }
                    let lo = i
                    while i < end, !isGap(i) { i += 1 }
                    if i > lo { span(lo, i) }
                }
            case .lines:
                var hi = end
                while hi > start, isGap(hi - 1) { hi -= 1 }
                var lo = start
                while lo < hi, isGap(lo) { lo += 1 }
                if hi > lo { span(lo, hi) }
            }
        }
        return spans
    }
}
