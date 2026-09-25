import Foundation
import MotionModel

extension AnimatableProperty where Value: Interpolatable {
    /// The property's value at any moment, including between frames.
    ///
    /// Before the first keyframe the property holds the first keyframe's
    /// value, and after the last it holds the last one's. With no keyframes it
    /// is its static value at every moment.
    public func value(at time: Double) -> Value {
        let k = keyframes
        guard let first = k.first, let last = k.last else { return value }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }

        // The last keyframe at or before `time`. Keyframes are sorted, so a
        // binary search keeps long animations cheap to scrub.
        var lo = 0, hi = k.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if k[mid].time <= time { lo = mid } else { hi = mid }
        }
        let a = k[lo], b = k[lo + 1]
        let span = b.time - a.time
        guard span > 0 else { return b.value }
        let u = (time - a.time) / span
        return Value.interpolate(a.value, b.value, a.easing.progress(u))
    }
}
