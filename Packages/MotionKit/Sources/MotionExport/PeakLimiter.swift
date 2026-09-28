import Foundation

/// Keeps a mix's peaks under a ceiling, so clips that overlap loudly never
/// clip. Sound that stays under the ceiling passes through unchanged.
///
/// A look-ahead brickwall. Each frame has a target: the gain that brings its
/// loudest channel down to the ceiling, or 1. A frame's gain starts from the
/// lowest target among it and the `lookahead - 1` frames after it (a running
/// minimum), which drops at once and comes back up slowly (the release), and
/// is then averaged over the last `lookahead` frames. Every frame in that
/// average saw the frame being sent within its own look-ahead, so the
/// average cannot rise above what that frame needs: nothing goes over, and
/// the gain glides down over the look-ahead instead of jumping. The output
/// runs `lookahead - 1` frames behind the input; `flush` sends the rest.
struct PeakLimiter {
    /// −1 dBFS: a little under full scale, so encoders and players that
    /// overshoot between samples stay clean.
    static let defaultCeiling: Float = 0.891
    let ceiling: Float
    let channels: Int
    let lookahead: Int
    private let release: Float

    /// Frames taken but not yet sent, interleaved, and each one's target.
    private var held: [Float] = []
    private var targets: [Float] = []
    /// Indices (into all frames taken) of rising targets, front first: the
    /// running minimum.
    private var window: [Int] = []
    /// The last `lookahead` released gains, for the average, and their sum.
    private var recent: [Float]
    private var recentIndex = 0
    private var recentSum: Float
    private var released: Float = 1
    private var taken = 0
    private var sent = 0

    init(ceiling: Float = PeakLimiter.defaultCeiling, channels: Int = 2, sampleRate: Double = 48000,
         lookaheadSeconds: Double = 0.005, releaseSeconds: Double = 0.15) {
        self.ceiling = ceiling
        self.channels = channels
        lookahead = max(Int(sampleRate * lookaheadSeconds), 1)
        release = Float(1 - exp(-1 / (sampleRate * releaseSeconds)))
        recent = Array(repeating: 1, count: lookahead)
        recentSum = Float(lookahead)
    }

    /// Takes interleaved frames and returns those now ready, limited.
    mutating func process(_ input: [Float]) -> [Float] {
        let count = input.count / channels
        var out: [Float] = []
        out.reserveCapacity(count * channels)
        for f in 0..<count {
            var peak: Float = 0
            for c in 0..<channels {
                let v = input[f * channels + c]
                held.append(v)
                peak = max(peak, abs(v))
            }
            let target = peak > ceiling ? ceiling / peak : 1
            targets.append(target)
            while let last = window.last, targets[last - base] >= target { window.removeLast() }
            window.append(taken)
            taken += 1
            // Once a frame has its whole look-ahead, it goes.
            if taken - sent >= lookahead { send(into: &out) }
        }
        compact()
        return out
    }

    /// Everything still held back, limited.
    mutating func flush() -> [Float] {
        var out: [Float] = []
        while sent < taken { send(into: &out) }
        compact()
        return out
    }

    private mutating func send(into out: inout [Float]) {
        let i = sent
        while let front = window.first, front < i { window.removeFirst() }
        let minimum = window.first.map { targets[$0 - base] } ?? 1
        released = min(minimum, released + (1 - released) * release)
        recentSum += released - recent[recentIndex]
        recent[recentIndex] = released
        recentIndex = (recentIndex + 1) % lookahead
        var gain = recentSum / Float(lookahead)
        // The first frames average in gains from before the sound began, so
        // they also keep to their own.
        if i < lookahead { gain = min(gain, released) }
        let at = (i - base) * channels
        for c in 0..<channels { out.append(held[at + c] * gain) }
        sent += 1
    }

    /// Where `held` and `targets` start, as an index into all frames taken.
    private var base = 0

    /// Drops what has been sent from the front of the buffers.
    private mutating func compact() {
        let done = sent - base
        guard done > 0 else { return }
        held.removeFirst(done * channels)
        targets.removeFirst(done)
        base = sent
    }
}
