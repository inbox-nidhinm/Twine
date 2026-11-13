import Foundation

/// One property's value at every exported frame, before it becomes Lottie
/// keyframes. Twine works every frame out exactly (springs, presets, letter
/// by letter text and all), and the export keeps only the frames a straight
/// line between neighbours cannot stand in for, so a still property is one
/// value and a steady move is two keyframes, while a spring keeps as many as
/// its curve needs.
struct Series {
    /// The value at each frame, every one the same length while its shape
    /// is the same.
    var values: [[Double]]
    /// What the value is made of at each frame (how many points a path has,
    /// whether it is closed): Lottie can only blend between values of one
    /// shape, so a change holds the old value until the frame it changes.
    var shapes: [Int]
    /// How far a straight line may stray from a frame's true value, in the
    /// value's own units as Lottie reads them.
    var tolerance: Double

    init(values: [[Double]], shapes: [Int]? = nil, tolerance: Double) {
        self.values = values
        self.shapes = shapes ?? Array(repeating: 0, count: values.count)
        self.tolerance = tolerance
    }

    struct Keyframe: Equatable {
        var frame: Int
        var value: [Double]
        /// Stays at this value until the next keyframe, rather than moving
        /// towards it.
        var holds: Bool
    }

    var isStill: Bool { keyframes().count == 1 }

    /// The fewest keyframes that, joined by straight lines, pass within
    /// `tolerance` of every frame's value. Found in one sweep (the swinging
    /// door): from each keyframe, the slopes a line may take to stay within
    /// reach of every frame passed so far narrow as it goes, and the line
    /// ends at the furthest frame whose own value lies inside them.
    func keyframes() -> [Keyframe] {
        let n = values.count
        guard n > 0 else { return [] }
        var out: [Keyframe] = []
        var i = 0
        while true {
            if i == n - 1 {
                out.append(Keyframe(frame: i, value: values[i], holds: false))
                break
            }
            if shapes[i + 1] != shapes[i] || values[i + 1].count != values[i].count {
                out.append(Keyframe(frame: i, value: values[i], holds: true))
                i += 1
                continue
            }
            let start = values[i]
            let d = start.count
            var lo = [Double](repeating: -.infinity, count: d), hi = [Double](repeating: .infinity, count: d)
            var best = i + 1
            var j = i + 1
            sweep: while j < n, shapes[j] == shapes[i], values[j].count == d {
                let span = Double(j - i)
                let v = values[j]
                var fits = true
                for k in 0..<d {
                    let slope = (v[k] - start[k]) / span
                    if slope < lo[k] - 1e-12 || slope > hi[k] + 1e-12 { fits = false; break }
                }
                if fits { best = j }
                for k in 0..<d {
                    lo[k] = max(lo[k], (v[k] - tolerance - start[k]) / span)
                    hi[k] = min(hi[k], (v[k] + tolerance - start[k]) / span)
                    if lo[k] > hi[k] { break sweep }
                }
                j += 1
            }
            out.append(Keyframe(frame: i, value: start, holds: false))
            i = best
        }
        // A last run of one value needs no keyframe at its end: a player
        // holds the last keyframe's value.
        while out.count >= 2, out[out.count - 1].value == out[out.count - 2].value { out.removeLast() }
        return out
    }
}

/// How a property's values are written.
enum LottieValueKind {
    /// One number: written bare when still, in a list in keyframes.
    case scalar
    /// Several numbers, always in a list.
    case vector
    /// A position, whose keyframes take single easing numbers, as Lottie's
    /// own exporter writes them.
    case spatial
    /// Paths, rebuilt from their numbers by `make`.
    case shape(make: ([Double]) -> LottieJSON)
}

extension Series {
    /// The property as Lottie writes it: `{"a":0,"k":value}` when still,
    /// keyframes joined by straight lines otherwise.
    func property(_ kind: LottieValueKind) -> LottieJSON {
        let frames = keyframes()
        func value(_ v: [Double]) -> LottieJSON {
            switch kind {
            case .scalar: .number(v.first ?? 0)
            case .vector, .spatial: .numbers(v)
            case .shape(let make): make(v)
            }
        }
        guard frames.count > 1 else {
            return .object([("a", .number(0)), ("k", value(frames.first?.value ?? []))])
        }
        let bare: Bool
        switch kind {
        case .spatial, .shape: bare = true
        case .scalar, .vector: bare = false
        }
        func ease(_ x: Double) -> LottieJSON {
            bare ? .object([("x", .number(x)), ("y", .number(x))])
                : .object([("x", .numbers([x])), ("y", .numbers([x]))])
        }
        let keys: [LottieJSON] = frames.enumerated().map { index, key in
            var pairs: [(String, LottieJSON)] = [("t", .number(Double(key.frame)))]
            switch kind {
            case .vector, .spatial: pairs.append(("s", value(key.value)))
            case .scalar, .shape: pairs.append(("s", .array([value(key.value)])))
            }
            if index < frames.count - 1 {
                if key.holds {
                    pairs.append(("h", .number(1)))
                } else {
                    pairs.append(("o", ease(0)))
                    pairs.append(("i", ease(1)))
                }
            }
            return .object(pairs)
        }
        return .object([("a", .number(1)), ("k", .array(keys))])
    }
}
