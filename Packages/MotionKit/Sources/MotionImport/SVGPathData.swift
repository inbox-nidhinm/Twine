import Foundation
import MotionModel
import MotionEvaluation

/// SVG path data (`d`) read into Twine's own paths: every command, relative
/// and absolute, with quadratic curves raised to cubics and arcs cut into
/// quarter-turn cubics, so the result is plain anchor points with handles.
enum SVGPathData {
    static func parse(_ d: String) -> BezierPath {
        var scanner = NumberScanner(d)
        var builder = PathBuilder()
        var command: Character?
        while true {
            scanner.skipSeparators()
            if let c = scanner.peekCommand() {
                command = c
                scanner.advance()
            } else if scanner.atEnd {
                break
            } else if command == nil {
                // Numbers before any command: not a path.
                break
            }
            guard let c = command else { break }
            let relative = c.isLowercase
            let base = relative ? builder.current : .zero
            func point() -> Vec2? {
                guard let x = scanner.number(), let y = scanner.number() else { return nil }
                return Vec2(base.x + x, base.y + y)
            }
            var ok = true
            switch c.uppercased().first! {
            case "M":
                guard let p = point() else { ok = false; break }
                builder.move(to: p)
                // Further pairs after a move are lines.
                command = relative ? "l" : "L"
            case "L":
                guard let p = point() else { ok = false; break }
                builder.line(to: p)
            case "H":
                guard let x = scanner.number() else { ok = false; break }
                builder.line(to: Vec2(relative ? builder.current.x + x : x, builder.current.y))
            case "V":
                guard let y = scanner.number() else { ok = false; break }
                builder.line(to: Vec2(builder.current.x, relative ? builder.current.y + y : y))
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { ok = false; break }
                builder.curve(c1, c2, p)
            case "S":
                guard let c2 = point(), let p = point() else { ok = false; break }
                builder.curve(builder.reflectedCubic, c2, p)
            case "Q":
                guard let q = point(), let p = point() else { ok = false; break }
                builder.quad(q, p)
            case "T":
                guard let p = point() else { ok = false; break }
                builder.quad(builder.reflectedQuad, p)
            case "A":
                guard let rx = scanner.number(), let ry = scanner.number(), let angle = scanner.number(),
                      let large = scanner.flag(), let sweep = scanner.flag(), let p = point() else { ok = false; break }
                builder.arc(rx: rx, ry: ry, rotation: angle, large: large, sweep: sweep, to: p)
            case "Z":
                builder.close()
                // A close takes no numbers; stop it repeating on the next.
                command = nil
                scanner.skipSeparators()
                if scanner.peekCommand() == nil && !scanner.atEnd { ok = false }
            default:
                ok = false
            }
            if !ok { break }
        }
        return builder.finished()
    }
}

/// Numbers and flags as SVG writes them: `1.5.5` is two numbers, `-1-2`
/// two more, and an arc's flags may run together, as `a1 1 0 01 1 1`.
struct NumberScanner {
    private let chars: [Character]
    private var i = 0

    init(_ text: String) { chars = Array(text) }

    var atEnd: Bool { i >= chars.count }

    mutating func advance() { i += 1 }

    mutating func skipSeparators() {
        while i < chars.count, chars[i].isWhitespace || chars[i] == "," { i += 1 }
    }

    func peekCommand() -> Character? {
        guard i < chars.count, chars[i].isLetter, chars[i] != "e", chars[i] != "E" else { return nil }
        return chars[i]
    }

    mutating func flag() -> Bool? {
        skipSeparators()
        guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return nil }
        defer { i += 1 }
        return chars[i] == "1"
    }

    mutating func number() -> Double? {
        skipSeparators()
        let start = i
        if i < chars.count, chars[i] == "+" || chars[i] == "-" { i += 1 }
        var digits = false, dot = false
        while i < chars.count {
            let c = chars[i]
            if c.isNumber { digits = true; i += 1 } else if c == ".", !dot { dot = true; i += 1 } else { break }
        }
        if digits, i < chars.count, chars[i] == "e" || chars[i] == "E" {
            var j = i + 1
            if j < chars.count, chars[j] == "+" || chars[j] == "-" { j += 1 }
            if j < chars.count, chars[j].isNumber {
                i = j
                while i < chars.count, chars[i].isNumber { i += 1 }
            }
        }
        guard digits else { i = start; return nil }
        // Past the limit counts as malformed, so a path stops there, as a
        // browser stops at a mistake.
        guard let value = SVGNumber.sane(Double(String(chars[start..<i]))) else { i = start; return nil }
        return value
    }
}

/// Builds subpaths of anchor points, each with handles relative to it.
struct PathBuilder {
    private(set) var subpaths: [Subpath] = []
    private var points: [PathPoint] = []
    private(set) var current = Vec2.zero
    private var start = Vec2.zero
    /// The last cubic's second control point, and the last quadratic's
    /// control point, for the smooth commands that mirror them.
    private var lastCubic: Vec2?
    private var lastQuad: Vec2?

    var reflectedCubic: Vec2 { lastCubic.map { Vec2(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current }
    var reflectedQuad: Vec2 { lastQuad.map { Vec2(2 * current.x - $0.x, 2 * current.y - $0.y) } ?? current }

    mutating func move(to p: Vec2) {
        endSubpath(closed: false)
        points = [PathPoint(p)]
        current = p
        start = p
        lastCubic = nil
        lastQuad = nil
    }

    private mutating func ensureStarted() {
        if points.isEmpty { points = [PathPoint(current)]; start = current }
    }

    mutating func line(to p: Vec2) {
        ensureStarted()
        points.append(PathPoint(p))
        current = p
        lastCubic = nil
        lastQuad = nil
    }

    mutating func curve(_ c1: Vec2, _ c2: Vec2, _ p: Vec2) {
        ensureStarted()
        points[points.count - 1].outHandle = c1 - current
        points.append(PathPoint(p, inHandle: c2 - p))
        current = p
        lastCubic = c2
        lastQuad = nil
    }

    mutating func quad(_ q: Vec2, _ p: Vec2) {
        let c1 = Vec2(current.x + 2 / 3 * (q.x - current.x), current.y + 2 / 3 * (q.y - current.y))
        let c2 = Vec2(p.x + 2 / 3 * (q.x - p.x), p.y + 2 / 3 * (q.y - p.y))
        curve(c1, c2, p)
        lastCubic = nil
        lastQuad = q
    }

    /// An elliptical arc as SVG draws one, from its end points, turned into
    /// cubics of at most a quarter turn each (SVG 1.1, appendix F.6).
    mutating func arc(rx: Double, ry: Double, rotation: Double, large: Bool, sweep: Bool, to p: Vec2) {
        let p0 = current
        var rx = abs(rx), ry = abs(ry)
        guard rx > 1e-9, ry > 1e-9, p0 != p else { return line(to: p) }
        let phi = rotation * .pi / 180
        let cosP = cos(phi), sinP = sin(phi)
        let dx = (p0.x - p.x) / 2, dy = (p0.y - p.y) / 2
        let x1 = cosP * dx + sinP * dy, y1 = -sinP * dx + cosP * dy
        let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den > 0 ? max(num / den, 0).squareRoot() : 0
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cosP * cx1 - sinP * cy1 + (p0.x + p.x) / 2
        let cy = sinP * cx1 + cosP * cy1 + (p0.y + p.y) / 2
        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        guard delta.isFinite, theta1.isFinite, cx.isFinite, cy.isFinite, rx.isFinite, ry.isFinite else { return line(to: p) }
        let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
        let step = delta / Double(segments)
        let k = 4 / 3 * tan(step / 4)
        func onEllipse(_ t: Double) -> Vec2 {
            let x = rx * cos(t), y = ry * sin(t)
            return Vec2(cosP * x - sinP * y + cx, sinP * x + cosP * y + cy)
        }
        func derivative(_ t: Double) -> Vec2 {
            let x = -rx * sin(t), y = ry * cos(t)
            return Vec2(cosP * x - sinP * y, sinP * x + cosP * y)
        }
        var t = theta1
        for s in 0..<segments {
            let t2 = t + step
            let a = onEllipse(t), b = s == segments - 1 ? p : onEllipse(t2)
            let da = derivative(t), db = derivative(t2)
            curve(Vec2(a.x + k * da.x, a.y + k * da.y), Vec2(b.x - k * db.x, b.y - k * db.y), b)
            t = t2
        }
        lastCubic = nil
    }

    mutating func close() {
        guard !points.isEmpty else { return }
        endSubpath(closed: true)
        current = start
        lastCubic = nil
        lastQuad = nil
    }

    private mutating func endSubpath(closed: Bool) {
        defer { points = [] }
        guard points.count > 1 || (points.count == 1 && closed) else { return }
        var list = points
        if closed, list.count > 1, let last = list.last, near(last.position, list[0].position) {
            // Ending where it began: the last point is the first again, so
            // its incoming handle belongs to the first.
            list[0].inHandle = last.inHandle
            list.removeLast()
        }
        subpaths.append(Subpath(points: list, isClosed: closed))
    }

    private func near(_ a: Vec2, _ b: Vec2) -> Bool { abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6 }

    mutating func finished() -> BezierPath {
        endSubpath(closed: false)
        return BezierPath(subpaths: subpaths)
    }
}

extension BezierPath {
    /// Every point and handle carried by `t`.
    func transformed(by t: Affine) -> BezierPath {
        BezierPath(subpaths: subpaths.map { sub in
            Subpath(points: sub.points.map {
                PathPoint(t.apply($0.position), inHandle: t.applyToVector($0.inHandle), outHandle: t.applyToVector($0.outHandle))
            }, isClosed: sub.isClosed)
        })
    }
}
