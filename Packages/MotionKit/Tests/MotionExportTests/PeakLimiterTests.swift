import Foundation
import Testing
@testable import MotionExport

/// A stereo sine at 440 Hz, interleaved, `seconds` long at 48 kHz.
private func sine(_ amplitude: Float, seconds: Double) -> [Float] {
    (0..<Int(seconds * 48000)).flatMap { i -> [Float] in
        let v = amplitude * Float(sin(Double(i) * 2 * .pi * 440 / 48000))
        return [v, v]
    }
}

/// All of a signal through a limiter, fed in uneven pieces as a reader
/// hands them over.
private func limited(_ signal: [Float], limiter: inout PeakLimiter) -> [Float] {
    var out: [Float] = []
    var at = 0
    var size = 1000
    while at < signal.count {
        let end = min(at + size * 2, signal.count)
        out += limiter.process(Array(signal[at..<end]))
        at = end
        size = size == 1000 ? 4096 : 1000
    }
    return out + limiter.flush()
}

@Suite struct PeakLimiterTests {
    @Test func loudSoundNeverPassesTheCeiling() {
        var limiter = PeakLimiter()
        let out = limited(sine(1.8, seconds: 0.5), limiter: &limiter)
        #expect(out.count == Int(0.5 * 48000) * 2)
        #expect(out.map(abs).max()! <= PeakLimiter.defaultCeiling + 1e-5)
    }

    @Test func quietSoundComesThroughUntouched() {
        var limiter = PeakLimiter()
        let signal = sine(0.5, seconds: 0.25)
        let out = limited(signal, limiter: &limiter)
        #expect(out.count == signal.count)
        #expect(zip(out, signal).allSatisfy { abs($0 - $1) < 1e-6 })
    }

    @Test func aSuddenPeakIsCaughtAndTheGainGlides() {
        // Quiet, then one loud burst that starts at once.
        let signal = sine(0.3, seconds: 0.2) + sine(1.5, seconds: 0.05) + sine(0.3, seconds: 1.0)
        var limiter = PeakLimiter()
        let out = limited(signal, limiter: &limiter)
        #expect(out.map(abs).max()! <= PeakLimiter.defaultCeiling + 1e-5)
        // No step in level bigger than the sine itself makes between samples:
        // the gain eases down rather than jumping.
        let left = stride(from: 0, to: out.count, by: 2).map { out[$0] }
        let steps = zip(left, left.dropFirst()).map { abs($1 - $0) }
        #expect(steps.max()! < 0.1)
        // A second after the burst (the release is 150 ms), the quiet part is
        // back to full level.
        let tail = Array(left.suffix(2400))
        #expect(abs(tail.map(abs).max()! - 0.3) < 0.01)
    }
}
