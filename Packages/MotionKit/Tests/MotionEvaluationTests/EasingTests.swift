import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

@Suite struct EasingTests {
    @Test func everyEasingStartsAtZeroAndEndsAtOne() {
        var easings: [Easing] = [.linear, .custom(.easeInOut), .custom(CubicBezier(0.34, 1.56, 0.64, 1))]
        for preset in EasingPreset.allCases {
            for intensity in [0.0, 0.5, 1.0] { easings.append(.preset(preset, intensity: intensity)) }
        }
        for easing in easings {
            #expect(easing.progress(0) == 0)
            #expect(easing.progress(1) == 1)
            #expect(easing.progress(-0.5) == 0)
            #expect(easing.progress(1.5) == 1)
        }
    }

    @Test func theBackEasingsAreTheUsersCurvesAndGrowWithIntensity() {
        let outBack = CubicBezier(0.45, 1.45, 0.8, 1), inBack = CubicBezier(0.3, -0.05, 0.7, -0.5)
        for u in stride(from: 0.05, through: 0.95, by: 0.05) {
            #expect(abs(EasingPreset.easeOutBack.progress(u, intensity: 0.5) - outBack.value(at: u)) < 1e-9)
            #expect(abs(EasingPreset.easeInBack.progress(u, intensity: 0.5) - inBack.value(at: u)) < 1e-9)
        }
        let samples = stride(from: 0.0, through: 1, by: 0.01)
        func peak(_ i: Double) -> Double { samples.map { EasingPreset.easeOutBack.progress($0, intensity: i) }.max()! }
        func dip(_ i: Double) -> Double { samples.map { EasingPreset.easeInBack.progress($0, intensity: i) }.min()! }
        // Out back passes the end, in back goes below the start, more so as intensity rises.
        #expect(peak(0.5) > 1.05)
        #expect(peak(1) > peak(0.5))
        #expect(abs(peak(0) - 1) < 1e-9)
        #expect(dip(0.5) < -0.05)
        #expect(dip(1) < dip(0.5))
        #expect(abs(dip(0)) < 1e-9)
    }

    @Test func linearIsTheIdentity() {
        for u in stride(from: 0.0, through: 1, by: 0.1) {
            #expect(abs(Easing.linear.progress(u) - u) < 1e-12)
        }
    }

    @Test func bezierMatchesKnownValues() {
        // Reference values for CSS `ease-in-out` (0.42, 0, 0.58, 1), which is
        // symmetric: halfway in time is halfway in progress.
        let curve = CubicBezier.easeInOut
        #expect(abs(curve.value(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(curve.value(at: 0.25) + curve.value(at: 0.75) - 1) < 1e-6)
        // Ease-in starts slow, ease-out starts fast.
        #expect(CubicBezier(0.42, 0, 1, 1).value(at: 0.25) < 0.25)
        #expect(CubicBezier(0, 0, 0.58, 1).value(at: 0.25) > 0.25)
        // A diagonal curve is linear.
        #expect(abs(CubicBezier(0.25, 0.25, 0.75, 0.75).value(at: 0.3) - 0.3) < 1e-9)
    }

    @Test func bezierIsMonotonicForAnOrdinaryCurve() {
        var last = -1.0
        for u in stride(from: 0.0, through: 1, by: 0.01) {
            let v = CubicBezier.easeInOut.value(at: u)
            #expect(v >= last)
            last = v
        }
    }

    @Test func backCurvesOvershoot() {
        let backOut = CubicBezier(0.34, 1.56, 0.64, 1)
        let peak = stride(from: 0.0, through: 1, by: 0.01).map(backOut.value(at:)).max()!
        #expect(peak > 1.05)
    }
}

@Suite struct PresetTests {
    private func peak(_ easing: Easing) -> Double {
        stride(from: 0.0, through: 1, by: 0.005).map(easing.progress).max()!
    }

    @Test func noneIsLinearAtAnyIntensity() {
        for i in [0.0, 1.0] {
            #expect(abs(Easing.preset(.none, intensity: i).progress(0.3) - 0.3) < 1e-12)
        }
    }

    @Test func curvePresetsAreNearlyLinearAtNoIntensity() {
        for preset in [EasingPreset.smooth, .slowDown, .accelerate] {
            #expect(abs(Easing.preset(preset, intensity: 0).progress(0.3) - 0.3) < 1e-6)
        }
    }

    @Test func eachPresetHasItsShape() {
        #expect(Easing.preset(.slowDown, intensity: 0.5).progress(0.25) > 0.25)
        #expect(Easing.preset(.accelerate, intensity: 0.5).progress(0.25) < 0.25)
        let smooth = Easing.preset(.smooth, intensity: 0.5)
        #expect(smooth.progress(0.1) < 0.1 && smooth.progress(0.8) > 0.8)
    }

    @Test func theStandardIntensityIsTheDesignersCurve() {
        let beziers: [(EasingPreset, CubicBezier)] = [(.smooth, CubicBezier(0.5, 0, 0, 1)), (.natural, CubicBezier(0.8, 0, 0.2, 1)),
                                                       (.slowDown, CubicBezier(0, 0, 0, 1)), (.accelerate, CubicBezier(1, 0, 1, 1))]
        for (preset, curve) in beziers {
            for u in [0.1, 0.3, 0.5, 0.9] {
                #expect(abs(Easing.preset(preset, intensity: 0.5).progress(u) - curve.value(at: u)) < 1e-9, "\(preset)")
            }
        }
        // The lists, at their own points: a quarter of the way is the 26th.
        #expect(abs(Easing.preset(.spring, intensity: 0.5).progress(0.25) - 1.081) < 1e-9)
        #expect(abs(Easing.preset(.bounce, intensity: 0.5).progress(0.5) - 0.7497) < 1e-9)
        #expect(abs(Easing.preset(.overshoot, intensity: 0.5).progress(0.25) - 1.2) < 1e-9)
        #expect(abs(Easing.preset(.impulse, intensity: 0.5).progress(0.3) - -0.2) < 1e-9)
        #expect(abs(Easing.preset(.swing, intensity: 0.5).progress(0.6) - 1.1) < 1e-9)
        // Between points, a straight line.
        #expect(abs(Easing.preset(.overshoot, intensity: 0.5).progress(0.005) - 0.1739 / 2) < 1e-9)
    }

    @Test func curvesGrowStrongerPastTheStandardAndStayInside() {
        for preset in [EasingPreset.smooth, .natural, .slowDown, .accelerate] {
            let samples = (0...100).map { Easing.preset(preset, intensity: 1).progress(Double($0) / 100) }
            #expect(samples.allSatisfy { $0 >= -1e-9 && $0 <= 1 + 1e-9 }, "\(preset)")
        }
        #expect(Easing.preset(.slowDown, intensity: 1).progress(0.1) > Easing.preset(.slowDown, intensity: 0.5).progress(0.1))
        #expect(Easing.preset(.accelerate, intensity: 1).progress(0.9) < Easing.preset(.accelerate, intensity: 0.5).progress(0.9))
    }

    @Test func strongerIntensityIsAStrongerCurve() {
        #expect(Easing.preset(.slowDown, intensity: 1).progress(0.2) > Easing.preset(.slowDown, intensity: 0.3).progress(0.2))
    }

    @Test func overshootPassesTheEndOnlyWithIntensity() {
        #expect(peak(.preset(.overshoot, intensity: 0)) <= 1.0000001)
        #expect(peak(.preset(.overshoot, intensity: 0.5)) > 1.02)
        #expect(peak(.preset(.overshoot, intensity: 1)) > peak(.preset(.overshoot, intensity: 0.5)))
    }

    @Test func springBouncesMoreWithIntensity() {
        #expect(peak(.preset(.spring, intensity: 0)) <= 1.0001)
        #expect(peak(.preset(.spring, intensity: 0.5)) > 1.05)
        #expect(peak(.preset(.spring, intensity: 1)) > peak(.preset(.spring, intensity: 0.5)))
    }

    @Test func naturalIsSymmetric() {
        let natural = Easing.preset(.natural, intensity: 0.5)
        #expect(abs(natural.progress(0.5) - 0.5) < 1e-6)
        #expect(abs(natural.progress(0.2) + natural.progress(0.8) - 1) < 1e-6)
    }

    @Test func bounceLandsAndBouncesOnTheEnd() {
        let samples = (0...2000).map { Easing.preset(.bounce, intensity: 0.5).progress(Double($0) / 2000) }
        // Never past the end: it bounces off it.
        #expect(samples.allSatisfy { $0 <= 1 + 1e-9 })
        // It touches the end, leaves it and comes back several times.
        var touches = 0
        for (a, b) in zip(samples, samples.dropFirst()) where a < 0.98 && b >= 0.98 { touches += 1 }
        #expect(touches >= 3)
        // Higher bounces with more intensity.
        func lowestAfterFirstLanding(_ i: Double) -> Double {
            let s = (0...2000).map { Easing.preset(.bounce, intensity: i).progress(Double($0) / 2000) }
            let landed = s.firstIndex { $0 >= 0.98 } ?? 0
            return s[landed...].min() ?? 1
        }
        #expect(lowestAfterFirstLanding(1) < lowestAfterFirstLanding(0.2))
    }

    @Test func impulsePullsBackAndSwingAlsoOvershoots() {
        func lowest(_ easing: Easing) -> Double { (0...200).map { easing.progress(Double($0) / 200) }.min() ?? 0 }
        #expect(lowest(.preset(.impulse, intensity: 0.5)) < -0.05)
        #expect(peak(.preset(.impulse, intensity: 0.5)) <= 1.0000001)
        #expect(lowest(.preset(.impulse, intensity: 1)) < lowest(.preset(.impulse, intensity: 0.5)))
        #expect(lowest(.preset(.swing, intensity: 0.5)) < -0.05)
        #expect(peak(.preset(.swing, intensity: 0.5)) > 1.05)
    }

    @Test func intensityOutsideItsRangeIsClamped() {
        #expect(Easing.preset(.overshoot, intensity: 7).progress(0.4) == Easing.preset(.overshoot, intensity: 1).progress(0.4))
    }
}

@Suite struct SpringTests {
    @Test func startsAtRestAndSettlesOnTheTarget() {
        let spring = Spring()
        #expect(spring.position(at: 0) == 0)
        #expect(abs(spring.position(at: spring.settleDuration) - 1) <= 0.001)
        #expect(abs(spring.position(at: spring.settleDuration * 3) - 1) < 0.001)
    }

    @Test func underdampedSpringsOvershoot() {
        let bouncy = Spring(stiffness: 200, damping: 8, mass: 1)
        let peak = stride(from: 0.0, to: bouncy.settleDuration, by: 0.005).map(bouncy.position(at:)).max()!
        #expect(peak > 1.2)
    }

    @Test func criticalAndOverdampedSpringsNeverOvershoot() {
        // Critical damping is 2·sqrt(k·m).
        for spring in [Spring(stiffness: 100, damping: 20, mass: 1), Spring(stiffness: 100, damping: 60, mass: 1)] {
            let peak = stride(from: 0.0, to: spring.settleDuration, by: 0.005).map(spring.position(at:)).max()!
            #expect(peak <= 1.0000001)
        }
    }

    @Test func stifferSpringsSettleSooner() {
        #expect(Spring(stiffness: 400, damping: 30).settleDuration < Spring(stiffness: 100, damping: 30).settleDuration)
    }

    @Test func settleTimeIsReallyWhereItStaysSettled() {
        for spring in [Spring(), Spring(stiffness: 300, damping: 10, mass: 2), Spring(stiffness: 50, damping: 40, mass: 1)] {
            let settle = spring.settleDuration
            for t in stride(from: settle, to: settle + 5, by: 0.01) {
                #expect(abs(spring.position(at: t) - 1) <= 0.0011)
            }
        }
    }

    @Test func undampedSpringsAreCapped() {
        #expect(Spring(stiffness: 100, damping: 0, mass: 1).settleDuration == 30)
    }

    @Test func aStretchedSpringKeepsItsShape() {
        // However long the action, halfway through it is halfway through the
        // spring's own motion.
        let spring = Spring(stiffness: 180, damping: 12, mass: 1)
        let natural = spring.position(at: spring.settleDuration * 0.5)
        #expect(abs(spring.normalizedProgress(0.5) - (natural + (1 - spring.position(at: spring.settleDuration)) * 0.5)) < 1e-12)
    }
}
