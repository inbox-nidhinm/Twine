import Foundation
import MotionModel

extension Easing {
    /// Eased progress through an action, for linear progress `u` from 0 to 1.
    /// The result is 0 at the start and exactly 1 at the end, and may overshoot
    /// in between.
    public func progress(_ u: Double) -> Double {
        if u <= 0 { return 0 }
        if u >= 1 { return 1 }
        switch self {
        case .custom(let curve): return curve.value(at: u)
        case .preset(let preset, let intensity): return preset.progress(u, intensity: intensity)
        }
    }
}

extension EasingPreset {
    /// Each preset's shape at an intensity from 0 to 1. The curves run from
    /// gentle at 0 to strong at 1, and 0.5 is a sensible middle.
    public func progress(_ u: Double, intensity: Double) -> Double {
        let i = min(max(intensity, 0), 1)
        switch self {
        case .none: return u
        case .smooth, .slowDown, .accelerate, .overshoot: return curve(intensity: i).value(at: u)
        case .spring: return Self.spring(intensity: i).normalizedProgress(u)
        }
    }

    /// The bezier a curve preset makes. Smooth, Slow down and Accelerate
    /// blend from a straight line at intensity 0 to a strong exponential
    /// curve at 1. Overshoot raises its first handle above the end value,
    /// further the higher the intensity.
    public func curve(intensity i: Double) -> CubicBezier {
        func blend(_ strong: CubicBezier) -> CubicBezier {
            let a = CubicBezier.linear
            return CubicBezier(a.x1 + (strong.x1 - a.x1) * i, a.y1 + (strong.y1 - a.y1) * i,
                               a.x2 + (strong.x2 - a.x2) * i, a.y2 + (strong.y2 - a.y2) * i)
        }
        switch self {
        case .none, .spring: return .linear
        case .smooth: return blend(CubicBezier(0.87, 0, 0.13, 1))
        case .slowDown: return blend(CubicBezier(0.16, 1, 0.3, 1))
        case .accelerate: return blend(CubicBezier(0.7, 0, 0.84, 0))
        case .overshoot: return CubicBezier(0.34, 1 + 1.2 * i, 0.64, 1)
        }
    }

    /// Critically damped (no bounce) at intensity 0, down to very little
    /// damping at 1. Stiffness only sets the natural speed, which fitting the
    /// motion to the action's duration cancels out.
    static func spring(intensity i: Double) -> Spring {
        let zeta = 1 - 0.92 * i
        let stiffness = 100.0
        return Spring(stiffness: stiffness, damping: 2 * zeta * stiffness.squareRoot(), mass: 1)
    }
}

extension CubicBezier {
    /// The curve's y for a given x, the way CSS timing functions work: x is
    /// time, y is progress. Solved for the curve parameter with Newton's
    /// method, falling back to bisection where the slope is too flat for it.
    public func value(at x: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // A curve whose control points sit on the diagonal is linear.
        if x1 == y1 && x2 == y2 { return x }

        func bx(_ t: Double) -> Double { ((1 - 3 * x2 + 3 * x1) * t + (3 * x2 - 6 * x1)) * t * t + 3 * x1 * t }
        func by(_ t: Double) -> Double { ((1 - 3 * y2 + 3 * y1) * t + (3 * y2 - 6 * y1)) * t * t + 3 * y1 * t }
        func dbx(_ t: Double) -> Double { 3 * (1 - 3 * x2 + 3 * x1) * t * t + 2 * (3 * x2 - 6 * x1) * t + 3 * x1 }

        var t = x
        for _ in 0..<8 {
            let error = bx(t) - x
            if abs(error) < 1e-7 { return by(t) }
            let slope = dbx(t)
            if abs(slope) < 1e-6 { break }
            t -= error / slope
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0..<60 {
            let v = bx(t)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return by(t)
    }
}

extension Spring {
    /// How far a spring released from 0 towards 1 has travelled after `time`
    /// seconds, from the closed-form solution of a damped oscillator starting
    /// at rest. Overshoots past 1 when underdamped.
    public func position(at time: Double) -> Double {
        let k = max(stiffness, 1e-6), c = max(damping, 0), m = max(mass, 1e-6)
        let w0 = sqrt(k / m)
        let zeta = c / (2 * sqrt(k * m))
        let t = max(time, 0)
        // Near critical damping the other two forms divide by nearly zero, so
        // a band around it uses the critical form, which is continuous there.
        if abs(zeta - 1) < 1e-4 {
            return 1 - exp(-w0 * t) * (1 + w0 * t)
        } else if zeta < 1 {
            let wd = w0 * sqrt(1 - zeta * zeta)
            let envelope = exp(-zeta * w0 * t)
            return 1 - envelope * (cos(wd * t) + (zeta * w0 / wd) * sin(wd * t))
        } else {
            let root = sqrt(zeta * zeta - 1)
            let r1 = -w0 * (zeta - root), r2 = -w0 * (zeta + root)
            return 1 - (r2 * exp(r1 * t) - r1 * exp(r2 * t)) / (r2 - r1)
        }
    }

    /// The time after which the spring stays within a thousandth of its
    /// target for good: the spring's natural length, which the spring preset
    /// stretches or squeezes to the action's duration.
    ///
    /// Worked out from the motion's envelope rather than by stepping through
    /// it, because evaluation asks for this on every frame. An underdamped
    /// spring's distance from the target never exceeds a decaying envelope, so
    /// the moment the envelope falls under the tolerance is solved directly.
    /// A critically damped or overdamped spring approaches without crossing,
    /// so its distance falls steadily and a bisection finds the moment. A
    /// spring with no damping never settles and is capped at thirty seconds.
    public var settleDuration: Double {
        let tolerance = 0.001
        let limit = 30.0
        let k = max(stiffness, 1e-6), c = max(damping, 0), m = max(mass, 1e-6)
        let w0 = sqrt(k / m)
        let zeta = c / (2 * sqrt(k * m))
        guard zeta > 1e-6 else { return limit }
        if zeta < 1 - 1e-4 {
            let wd = w0 * sqrt(1 - zeta * zeta)
            let amplitude = sqrt(1 + pow(zeta * w0 / wd, 2))
            return min(max(log(amplitude / tolerance) / (zeta * w0), 1e-3), limit)
        }
        var lo = 0.0, hi = limit
        guard abs(position(at: hi) - 1) <= tolerance else { return limit }
        for _ in 0..<60 {
            let mid = (lo + hi) / 2
            if abs(position(at: mid) - 1) > tolerance { lo = mid } else { hi = mid }
        }
        return max(hi, 1e-3)
    }

    /// Progress for linear progress `u` through an action of any length. The
    /// spring's natural motion is stretched or squeezed to fit, and nudged by
    /// the small amount left at the settle point so the action ends exactly
    /// on its end value rather than a thousandth short of it.
    func normalizedProgress(_ u: Double) -> Double {
        let settle = settleDuration
        let end = position(at: settle)
        return position(at: u * settle) + (1 - end) * u
    }
}
