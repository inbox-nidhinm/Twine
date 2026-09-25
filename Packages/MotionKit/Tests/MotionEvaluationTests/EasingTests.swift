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
        #expect(smooth.progress(0.2) < 0.2 && smooth.progress(0.8) > 0.8)
        #expect(abs(smooth.progress(0.5) - 0.5) < 1e-6)
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
