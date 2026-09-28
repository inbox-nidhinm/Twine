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
    /// Each preset's shape at an intensity from 0 to 1. At the standard 0.5
    /// it is exactly the designer's curve (the user's values, 28 September
    /// 2026); lower fades it towards a straight line, reaching one at 0;
    /// higher makes it stronger.
    public func progress(_ u: Double, intensity: Double) -> Double {
        let i = min(max(intensity, 0), 1)
        switch self {
        case .none:
            return u
        case .smooth, .natural, .slowDown, .accelerate:
            // Up to the standard, the bezier itself, its handles drawn in
            // towards the line. Past it, towards the curve applied twice,
            // which is stronger and still never leaves 0...1.
            guard i > 0.5, let own = designCurve else { return curve(intensity: i).value(at: u) }
            let once = own.value(at: u)
            return once + (own.value(at: once) - once) * (i - 0.5) * 2
        case .bounce:
            // It falls as it does at the standard; intensity sets how deep
            // it bounces off the end, none at 0 and twice as deep at 1.
            let p = Self.sampled(EasingTables.bounce, at: u)
            guard u > Self.bounceLanding else { return p }
            return 1 - (1 - p) * i * 2
        case .spring, .overshoot, .impulse, .swing:
            // How far it strays from a straight line, none at 0 and twice
            // the standard's at 1.
            guard let table else { return u }
            return u + (Self.sampled(table, at: u) - u) * i * 2
        }
    }

    /// Whether the preset is a bezier, which `curve` gives exactly; the
    /// others are lists of points, so a custom curve starts from a plain ease.
    public var isCurve: Bool { designCurve != nil || self == .none }

    /// The designer's bezier, for the presets that are one.
    private var designCurve: CubicBezier? {
        switch self {
        case .smooth: return CubicBezier(0.5, 0, 0, 1)
        case .natural: return CubicBezier(0.8, 0, 0.2, 1)
        case .slowDown: return CubicBezier(0, 0, 0, 1)
        case .accelerate: return CubicBezier(1, 0, 1, 1)
        default: return nil
        }
    }

    /// The designer's list of points, for the presets that are one.
    private var table: [Double]? {
        switch self {
        case .spring: return EasingTables.elastic
        case .bounce: return EasingTables.bounce
        case .overshoot: return EasingTables.overshoot
        case .impulse: return EasingTables.impulse
        case .swing: return EasingTables.swing
        default: return nil
        }
    }

    /// When Bounce first reaches the end, a third of the way through.
    private static let bounceLanding = Double(EasingTables.bounce.firstIndex { $0 > 0.98 } ?? 0)
        / Double(EasingTables.bounce.count - 1)

    /// A list's value at `u`, joining its points with straight lines, as
    /// CSS's `linear()` does.
    static func sampled(_ table: [Double], at u: Double) -> Double {
        let position = min(max(u, 0), 1) * Double(table.count - 1)
        let k = min(Int(position), table.count - 2)
        let f = position - Double(k)
        return table[k] + (table[k + 1] - table[k]) * f
    }

    /// The bezier a curve preset makes, up to the standard intensity: its
    /// handles drawn from the straight line at 0 to the designer's at 0.5.
    /// Past it the preset is no bezier, so this stays at the designer's. A
    /// preset that is no bezier gives the straight line.
    public func curve(intensity i: Double) -> CubicBezier {
        guard let own = designCurve else { return .linear }
        let t = min(max(i, 0), 0.5) * 2
        let a = CubicBezier.linear
        return CubicBezier(a.x1 + (own.x1 - a.x1) * t, a.y1 + (own.y1 - a.y1) * t,
                           a.x2 + (own.x2 - a.x2) * t, a.y2 + (own.y2 - a.y2) * t)
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
