import Foundation
import MotionModel

/// A value that can be blended from an action's starting value to its end.
///
/// `t` is the eased progress through the action. It usually runs 0 to 1 but
/// may leave that range: overshooting curves and springs go past the end
/// value and come back, so conformances extrapolate rather than clamp, except
/// where a value outside its range means nothing (a colour channel, a radius).
public protocol Interpolatable: AnimatableValue {
    static func interpolate(_ a: Self, _ b: Self, _ t: Double) -> Self
}

@inline(__always)
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

extension Double: Interpolatable {
    public static func interpolate(_ a: Double, _ b: Double, _ t: Double) -> Double { lerp(a, b, t) }
}

extension Vec2: Interpolatable {
    public static func interpolate(_ a: Vec2, _ b: Vec2, _ t: Double) -> Vec2 {
        Vec2(lerp(a.x, b.x, t), lerp(a.y, b.y, t))
    }
}

extension Size2: Interpolatable {
    public static func interpolate(_ a: Size2, _ b: Size2, _ t: Double) -> Size2 {
        Size2(lerp(a.width, b.width, t), lerp(a.height, b.height, t))
    }
}

extension CornerRadii: Interpolatable {
    public static func interpolate(_ a: CornerRadii, _ b: CornerRadii, _ t: Double) -> CornerRadii {
        CornerRadii(topLeft: max(0, lerp(a.topLeft, b.topLeft, t)),
                    topRight: max(0, lerp(a.topRight, b.topRight, t)),
                    bottomRight: max(0, lerp(a.bottomRight, b.bottomRight, t)),
                    bottomLeft: max(0, lerp(a.bottomLeft, b.bottomLeft, t)))
    }
}

/// Colours blend in OKLab, a perceptual space, so red to blue passes through
/// purple rather than a muddy grey, and a fade between two colours of equal
/// lightness stays at that lightness. Alpha blends linearly.
extension RGBA: Interpolatable {
    public static func interpolate(_ a: RGBA, _ b: RGBA, _ t: Double) -> RGBA {
        if a == b { return a }
        let la = OKLab(a), lb = OKLab(b)
        let mixed = OKLab(L: lerp(la.L, lb.L, t), a: lerp(la.a, lb.a, t), b: lerp(la.b, lb.b, t))
        var out = mixed.rgba
        out.a = min(max(lerp(a.a, b.a, t), 0), 1)
        return out
    }
}

/// One stop blending into another. Whole gradients blend through
/// `Gradient.interpolate`, which pairs their stops up first.
extension GradientStop: Interpolatable {
    public static func interpolate(_ a: GradientStop, _ b: GradientStop, _ t: Double) -> GradientStop {
        GradientStop(position: lerp(a.position, b.position, t), color: .interpolate(a.color, b.color, t))
    }
}

/// Two gradients with the same number of stops blend stop by stop, so the
/// stops slide to their new places as their colours change. With different
/// counts both are sampled at every position either one has a stop, and the
/// colours blend at those fixed positions, so the change stays smooth and
/// nothing jumps. The geometry (where it starts and ends) travels too.
extension MotionModel.Gradient: Interpolatable {
    public static func interpolate(_ a: MotionModel.Gradient, _ b: MotionModel.Gradient, _ t: Double) -> MotionModel.Gradient {
        let sa = a.stops.sorted { $0.position < $1.position }, sb = b.stops.sorted { $0.position < $1.position }
        let stops: [GradientStop]
        if sa.count == sb.count {
            stops = zip(sa, sb).map { GradientStop.interpolate($0, $1, t) }
        } else {
            let positions = Array(Set(sa.map(\.position) + sb.map(\.position))).sorted()
            stops = positions.map { p in
                GradientStop(position: p, color: .interpolate(color(of: sa, at: p), color(of: sb, at: p), t))
            }
        }
        return MotionModel.Gradient(stops: stops, start: .interpolate(a.start, b.start, t),
                                    end: .interpolate(a.end, b.end, t))
    }

    /// The colour a gradient shows at `position`, as Core Animation draws it:
    /// straight between neighbouring stops, and flat beyond the first and last.
    static func color(of stops: [GradientStop], at position: Double) -> RGBA {
        guard let first = stops.first, let last = stops.last else { return RGBA(0, 0, 0, 0) }
        if position <= first.position { return first.color }
        if position >= last.position { return last.color }
        for (lo, hi) in zip(stops, stops.dropFirst()) where position <= hi.position {
            let span = hi.position - lo.position
            let f = span > 0 ? (position - lo.position) / span : 1
            return RGBA(lerp(lo.color.r, hi.color.r, f), lerp(lo.color.g, hi.color.g, f),
                        lerp(lo.color.b, hi.color.b, f), lerp(lo.color.a, hi.color.a, f))
        }
        return last.color
    }
}

/// A colour and a gradient blend by treating the colour as a gradient of
/// that colour alone, shaped like the other. Linear and radial gradients
/// cannot become one another, so the kind changes half way while the stops
/// and geometry blend throughout. Progress is kept to 0...1: a colour has
/// nothing to overshoot into.
extension Paint: Interpolatable {
    public static func interpolate(_ a: Paint, _ b: Paint, _ t: Double) -> Paint {
        let t = min(max(t, 0), 1)
        if t == 0 { return a }
        if t == 1 { return b }
        if case .solid(let ca) = a, case .solid(let cb) = b { return .solid(.interpolate(ca, cb, t)) }
        let g = MotionModel.Gradient.interpolate(a.gradient(shapedLike: b), b.gradient(shapedLike: a), t)
        let radial: Bool
        switch (a, b) {
        case (.solid, _): radial = b.isRadialGradient
        case (_, .solid): radial = a.isRadialGradient
        default: radial = t < 0.5 ? a.isRadialGradient : b.isRadialGradient
        }
        return radial ? .radialGradient(g) : .linearGradient(g)
    }

    /// The paint's own gradient, or for a colour, `other`'s gradient with
    /// every stop in this colour.
    func gradient(shapedLike other: Paint) -> MotionModel.Gradient {
        switch self {
        case .linearGradient(let g), .radialGradient(let g): return g
        case .solid(let color):
            switch other {
            case .linearGradient(var g), .radialGradient(var g):
                g.stops = g.stops.map { GradientStop(position: $0.position, color: color) }
                return g
            case .solid:
                return MotionModel.Gradient(stops: [GradientStop(position: 0, color: color), GradientStop(position: 1, color: color)])
            }
        }
    }
}

extension StrokeLook: Interpolatable {
    public static func interpolate(_ a: StrokeLook, _ b: StrokeLook, _ t: Double) -> StrokeLook {
        StrokeLook(width: max(0, lerp(a.width, b.width, t)), paint: .interpolate(a.paint, b.paint, t))
    }
}

extension TrimRange: Interpolatable {
    public static func interpolate(_ a: TrimRange, _ b: TrimRange, _ t: Double) -> TrimRange {
        TrimRange(start: min(max(lerp(a.start, b.start, t), 0), 1), end: min(max(lerp(a.end, b.end, t), 0), 1))
    }
}

/// A shadow with no opacity has no colour worth blending from, so it takes
/// the other side's colour and only fades: a shadow animating in from none
/// darkens in its own colour rather than passing through grey.
extension DropShadow: Interpolatable {
    public static func interpolate(_ a: DropShadow, _ b: DropShadow, _ t: Double) -> DropShadow {
        func invisible(_ s: DropShadow) -> Bool { s.opacity <= 0 || s.color.a <= 0 }
        var ca = a.color, cb = b.color
        if invisible(a) { ca = cb } else if invisible(b) { cb = ca }
        return DropShadow(color: .interpolate(ca, cb, t), offset: .interpolate(a.offset, b.offset, t),
                          blur: max(0, lerp(a.blur, b.blur, t)),
                          opacity: min(max(lerp(invisible(a) ? 0 : a.opacity, invisible(b) ? 0 : b.opacity, t), 0), 1),
                          spread: lerp(a.spread, b.spread, t))
    }
}

extension BackgroundBlur: Interpolatable {
    public static func interpolate(_ a: BackgroundBlur, _ b: BackgroundBlur, _ t: Double) -> BackgroundBlur {
        BackgroundBlur(radius: max(0, lerp(a.radius, b.radius, t)), blend: min(max(lerp(a.blend, b.blend, t), 0), 1))
    }
}

extension Array: Interpolatable where Element: Interpolatable {
    public static func interpolate(_ a: [Element], _ b: [Element], _ t: Double) -> [Element] {
        guard a.count == b.count else { return t < 1 ? a : b }
        return zip(a, b).map { Element.interpolate($0, $1, t) }
    }
}

/// Paths with the same structure (the same subpaths, each with the same number
/// of points) blend point by point. Anything else holds. Proper shape morphing
/// between unlike paths is planned for later and will replace the hold.
extension BezierPath: Interpolatable {
    public static func interpolate(_ a: BezierPath, _ b: BezierPath, _ t: Double) -> BezierPath {
        guard a.subpaths.count == b.subpaths.count,
              zip(a.subpaths, b.subpaths).allSatisfy({ $0.points.count == $1.points.count && $0.isClosed == $1.isClosed })
        else { return t < 1 ? a : b }
        return BezierPath(subpaths: zip(a.subpaths, b.subpaths).map { sa, sb in
            Subpath(points: zip(sa.points, sb.points).map { pa, pb in
                PathPoint(.interpolate(pa.position, pb.position, t),
                          inHandle: .interpolate(pa.inHandle, pb.inHandle, t),
                          outHandle: .interpolate(pa.outHandle, pb.outHandle, t))
            }, isClosed: sa.isClosed)
        })
    }
}

// MARK: - OKLab

/// Björn Ottosson's OKLab, from sRGB with the standard transfer curve.
struct OKLab: Equatable {
    var L: Double
    var a: Double
    var b: Double

    init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    init(_ c: RGBA) {
        let r = OKLab.linear(c.r), g = OKLab.linear(c.g), bl = OKLab.linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    var rgba: RGBA {
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGBA(OKLab.gamma(r), OKLab.gamma(g), OKLab.gamma(bl), 1)
    }

    static func linear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func gamma(_ c: Double) -> Double {
        let v = min(max(c, 0), 1)
        return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
    }
}
