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

/// Stops blend pairwise when both sides have the same number of them. When
/// the counts differ there is no honest pairing, so the value holds its
/// start until the action ends. (Resampling to match counts arrives with the
/// Color action.)
extension GradientStop: Interpolatable {
    public static func interpolate(_ a: GradientStop, _ b: GradientStop, _ t: Double) -> GradientStop {
        GradientStop(position: lerp(a.position, b.position, t), color: .interpolate(a.color, b.color, t))
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
