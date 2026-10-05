import Foundation
import MotionModel

/// How well a search typed into the ⌘K card matches a name: the rules that
/// rank what the card lists, kept here so they can be tested.
public enum SearchMatch {
    /// A score for `title` (higher is better), or nil when `query` does not
    /// match it at all. Letter case and accents are ignored. The whole name,
    /// then its start, then the start of any word, then every typed word
    /// starting a word, then the initials (`bf` for Bring Forward), then
    /// anywhere inside, and last the letters in order with gaps. `keywords`
    /// are other words for the same thing ("snapping" for Smart Guides),
    /// counted a little below the name. Shorter names win ties.
    public static func score(_ query: String, in title: String, keywords: [String] = []) -> Double? {
        let q = normalised(query)
        guard !q.isEmpty else { return 0 }
        let own = score(q, title)
        let other = keywords.compactMap { score(q, $0).map { $0 * 0.8 } }.max()
        guard let best = [own, other].compactMap({ $0 }).max() else { return nil }
        return best - Double(title.count) * 0.01
    }

    /// Lower case, without accents, with runs of spaces made one.
    public static func normalised(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func score(_ q: String, _ name: String) -> Double? {
        let t = normalised(name)
        guard !t.isEmpty else { return nil }
        if t == q { return 100 }
        if t.hasPrefix(q) { return 90 }
        let words = t.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 80 }
        let typed = q.split(separator: " ").map(String.init)
        if typed.count > 1, typed.allSatisfy({ w in words.contains { $0.hasPrefix(w) } }) { return 70 }
        if q.count >= 2, !q.contains(" "), String(words.compactMap(\.first)).hasPrefix(q) { return 65 }
        if t.contains(q) { return 60 }
        return q.count >= 2 ? inOrder(q, t) : nil
    }

    /// The letters of `q` found in order in `t`: worth more the closer
    /// together they are, nothing when they are not all there.
    private static func inOrder(_ q: String, _ t: String) -> Double? {
        var gaps = 0
        var rest = Substring(t)
        for c in q where c != " " {
            guard let i = rest.firstIndex(of: c) else { return nil }
            gaps += rest.distance(from: rest.startIndex, to: i)
            rest = rest[rest.index(after: i)...]
        }
        return max(10, 40 - Double(gaps) * 2)
    }
}

/// A value typed into the ⌘K card: a time to go to, or a number for one of
/// the selection's properties (`opacity 50`, `w 400`, `2.5s`, `f120`).
public enum TypedEntry: Equatable, Sendable {
    /// Go to this many seconds.
    case time(Double)
    /// Go to this frame.
    case frame(Int)
    /// Set the selected layers' property to this, in the inspector's units:
    /// pixels, degrees, or percent for opacity and scale.
    case property(TypedProperty, Double)

    /// What `text` asks for, the likeliest first. A plain number goes to a
    /// time, or a frame when times show as frames. Nothing when it is no
    /// number or no name Twine knows.
    public static func parse(_ text: String, framesShown: Bool = false) -> [TypedEntry] {
        let t = SearchMatch.normalised(text)
        guard !t.isEmpty else { return [] }

        // A time: `2.5s`, `2.5 sec`, `1:05`, `1:05.5`.
        if let seconds = clock(t) { return [.time(seconds)] }
        // A frame: `f120`, `frame 120`, `120f`.
        for (prefix, suffix) in [("frame ", ""), ("frame", ""), ("f ", ""), ("f", ""), ("", " frames"), ("", " frame"), ("", "f")] {
            guard t.hasPrefix(prefix), t.hasSuffix(suffix), t.count > prefix.count + suffix.count else { continue }
            let core = t.dropFirst(prefix.count).dropLast(suffix.count)
            if let n = Int(core), n >= 0 { return [.frame(n)] }
        }
        // A plain number.
        if let n = Double(t), n.isFinite, n >= 0 {
            if framesShown, n == n.rounded(), n < Double(Int32.max) { return [.frame(Int(n)), .time(n)] }
            return [.time(n)]
        }
        // A property and a number: `opacity 50`, `w:400`, `rot = 45°`, `x -20px`.
        guard let match = t.wholeMatch(of: /([a-z][a-z ]*?) *[:=]? *(-?[0-9]*\.?[0-9]+) *(?:px|deg|%|°|s)?/),
              let value = Double(match.2), value.isFinite, abs(value) <= FileSafety.limit,
              let property = TypedProperty.named(String(match.1)) else { return [] }
        return [.property(property, value)]
    }

    /// Seconds from `2.5s`, `2.5 sec`, `2.5 seconds`, `1:05` or `1:05.5`.
    private static func clock(_ t: String) -> Double? {
        for unit in [" seconds", " second", " secs", " sec", "seconds", "second", "secs", "sec", " s", "s"] where t.hasSuffix(unit) {
            if let n = Double(t.dropLast(unit.count)), n.isFinite, n >= 0 { return n }
        }
        let parts = t.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let m = Int(parts[0]), m >= 0, m < 100_000,
              let s = Double(parts[1]), s.isFinite, s >= 0, s < 60, !parts[1].isEmpty else { return nil }
        return Double(m) * 60 + s
    }
}

/// The properties a value can be typed for in the ⌘K card.
public enum TypedProperty: String, CaseIterable, Sendable {
    case x, y, width, height, rotation, opacity, scale, radius, duration

    /// What the card says it sets.
    public var title: String {
        switch self {
        case .x: "X"
        case .y: "Y"
        case .width: "Width"
        case .height: "Height"
        case .rotation: "Rotation"
        case .opacity: "Opacity"
        case .scale: "Scale"
        case .radius: "Corner Radius"
        case .duration: "Scene Length"
        }
    }

    /// The names it answers to. One letter only as itself; longer names
    /// also by their first two letters or more (`op`, `rot`, `wid`).
    var names: [String] {
        switch self {
        case .x: ["x"]
        case .y: ["y"]
        case .width: ["w", "width"]
        case .height: ["h", "height"]
        case .rotation: ["r", "rotation", "rotate", "angle", "turn"]
        case .opacity: ["o", "opacity", "alpha"]
        case .scale: ["s", "scale"]
        case .radius: ["radius", "corner radius", "corners", "corner"]
        case .duration: ["duration", "length", "scene length"]
        }
    }

    /// The property `name` stands for, if any: an exact name first, then
    /// the first whose longer name starts with it.
    public static func named(_ name: String) -> TypedProperty? {
        let n = SearchMatch.normalised(name)
        guard !n.isEmpty else { return nil }
        if let exact = allCases.first(where: { $0.names.contains(n) }) { return exact }
        guard n.count >= 2 else { return nil }
        return allCases.first { $0.names.contains { $0.count > 1 && $0.hasPrefix(n) } }
    }
}
