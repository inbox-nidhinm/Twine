import Foundation
import Testing
import MotionModel
@testable import MotionEvaluation

@Suite struct EasingTests {
    @Test func everyEasingStartsAtZeroAndEndsAtOne() {
        let easings: [Easing] = [.linear, .hold, .bezier(.easeInOut), .bezier(CubicBezier(0.34, 1.56, 0.64, 1)),
                                 .spring(Spring()), .spring(Spring(stiffness: 100, damping: 5, mass: 1))]
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

    @Test func holdStaysAtTheStartUntilTheEnd() {
        #expect(Easing.hold.progress(0.999) == 0)
        #expect(Easing.hold.progress(1) == 1)
    }

    @Test func bezierMatchesKnownValues() {
        // Reference values for CSS `ease-in-out` (0.42, 0, 0.58, 1), which is
        // symmetric: halfway in time is halfway in progress.
        let curve = CubicBezier.easeInOut
        #expect(abs(curve.value(at: 0.5) - 0.5) < 1e-6)
        #expect(abs(curve.value(at: 0.25) + curve.value(at: 0.75) - 1) < 1e-6)
        // Ease-in starts slow, ease-out starts fast.
        #expect(CubicBezier.easeIn.value(at: 0.25) < 0.25)
        #expect(CubicBezier.easeOut.value(at: 0.25) > 0.25)
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
        // Override: however long the segment, halfway through the segment is
        // halfway through the spring's own motion.
        let spring = Spring(stiffness: 180, damping: 12, mass: 1)
        let natural = spring.position(at: spring.settleDuration * 0.5)
        #expect(abs(Easing.spring(spring).progress(0.5) - (natural + (1 - spring.position(at: spring.settleDuration)) * 0.5)) < 1e-12)
    }
}
