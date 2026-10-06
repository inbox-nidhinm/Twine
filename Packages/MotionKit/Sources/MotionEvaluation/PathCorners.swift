import Foundation
import MotionModel

extension BezierPath {
    /// The path as drawn: every point with a corner radius rounded off, as
    /// Figma rounds a vector's points. A corner's curve starts `radius /
    /// tan(angle / 2)` along each side, as a circle touching both would,
    /// held to half of each side so two rounded corners never cross on a
    /// short one; curved sides are cut along their length. Smooth points,
    /// open ends and sharp points with no radius are kept as they are.
    public func roundingCorners() -> BezierPath {
        guard subpaths.contains(where: { $0.points.contains { $0.cornerRadius > 0 } }) else { return self }
        return BezierPath(subpaths: subpaths.map(PathCorners.rounding))
    }
}

enum PathCorners {
    /// One cubic: from a point, its two controls, to the next point.
    struct Piece {
        var p0, c1, c2, p1: Vec2
        /// No handles either end, so it is a line and is cut as one.
        var isStraight: Bool

        func point(at t: Double) -> Vec2 {
            let q = 1 - t
            let a = q * q * q, b = 3 * q * q * t, c = 3 * q * t * t, d = t * t * t
            return Vec2(a * p0.x + b * c1.x + c * c2.x + d * p1.x, a * p0.y + b * c1.y + c * c2.y + d * p1.y)
        }
    }

    /// How many steps a curve is measured in, as `PathTrim` does.
    static let samples = 16

    static func rounding(_ sub: Subpath) -> Subpath {
        let points = sub.points
        let n = points.count
        let count = sub.isClosed ? n : n - 1
        guard n >= 2, count > 0, points.contains(where: { $0.cornerRadius > 0 }) else { return sub }
        let pieces = (0..<count).map { k -> Piece in
            let a = points[k], b = points[(k + 1) % n]
            return Piece(p0: a.position, c1: a.position + a.outHandle, c2: b.position + b.inHandle, p1: b.position,
                         isStraight: a.outHandle == .zero && b.inHandle == .zero)
        }
        let tables = pieces.map(lengths)
        var cutStart = [Double](repeating: 0, count: count), cutEnd = cutStart
        // For each rounded point, its sides' directions away from it.
        var sides = [(back: Vec2, on: Vec2)?](repeating: nil, count: n)

        func incoming(_ i: Int) -> Int? { sub.isClosed ? (i - 1 + n) % n : (i > 0 ? i - 1 : nil) }
        func outgoing(_ i: Int) -> Int? { sub.isClosed || i < n - 1 ? i : nil }

        for i in 0..<n where points[i].cornerRadius > 0 {
            guard let kin = incoming(i), let kout = outgoing(i) else { continue }
            let a = pieces[kin], b = pieces[kout]
            // Back along the way in, and on along the way out.
            guard let u = firstDirection(from: a.p1, toward: [a.c2, a.c1, a.p0]),
                  let v = firstDirection(from: b.p0, toward: [b.c1, b.c2, b.p1]) else { continue }
            let angle = acos(min(max(u.x * v.x + u.y * v.y, -1), 1))
            // Nothing to round where the path runs straight on, or turns
            // right back on itself.
            guard angle > 1e-3, angle < .pi - 1e-3 else { continue }
            let distance = min(points[i].cornerRadius / tan(angle / 2),
                               tables[kin].last! / 2, tables[kout].last! / 2)
            guard distance > 1e-9 else { continue }
            cutEnd[kin] = distance
            cutStart[kout] = distance
            sides[i] = (u, v)
        }

        let cut = pieces.indices.map { k in
            trimmed(pieces[k], table: tables[k], from: cutStart[k], to: tables[k].last! - cutEnd[k])
        }
        var out: [PathPoint] = []
        out.reserveCapacity(n * 2)
        for i in 0..<n {
            let a = incoming(i).map { cut[$0] }, b = outgoing(i).map { cut[$0] }
            let inHandle = a.map { $0.c2 - $0.p1 } ?? points[i].inHandle
            let outHandle = b.map { $0.c1 - $0.p0 } ?? points[i].outHandle
            guard let side = sides[i], let a, let b else {
                out.append(PathPoint(points[i].position, inHandle: inHandle, outHandle: outHandle))
                continue
            }
            // Along each side where it was cut; a side cut away to nothing,
            // by two corners meeting at its middle, keeps its direction.
            let back = firstDirection(from: a.p1, toward: [a.c2, a.c1, a.p0]) ?? side.back
            let t1 = Vec2(-back.x, -back.y)
            let t2 = firstDirection(from: b.p0, toward: [b.c1, b.c2, b.p1]) ?? side.on
            // A circular arc from one cut to the other, leaving each along
            // its side: its turn and chord give its radius and handles.
            let turn = acos(min(max(t1.x * t2.x + t1.y * t2.y, -1), 1))
            let chord = hypot(b.p0.x - a.p1.x, b.p0.y - a.p1.y)
            let handle = turn > 1e-6 ? 4.0 / 3.0 * tan(turn / 4) * chord / (2 * sin(turn / 2)) : chord / 3
            out.append(PathPoint(a.p1, inHandle: inHandle, outHandle: Vec2(t1.x * handle, t1.y * handle)))
            out.append(PathPoint(b.p0, inHandle: Vec2(-t2.x * handle, -t2.y * handle), outHandle: outHandle))
        }
        return Subpath(points: out, isClosed: sub.isClosed)
    }

    /// The unit direction from `origin` to the first of `targets` that is
    /// not on it.
    static func firstDirection(from origin: Vec2, toward targets: [Vec2]) -> Vec2? {
        for t in targets {
            let d = t - origin, l = hypot(d.x, d.y)
            if l > 1e-9 { return Vec2(d.x / l, d.y / l) }
        }
        return nil
    }

    /// The length reached at each of `samples` even steps of the curve's
    /// parameter, from 0; the last is its whole length.
    static func lengths(_ piece: Piece) -> [Double] {
        if piece.isStraight { return [0, hypot(piece.p1.x - piece.p0.x, piece.p1.y - piece.p0.y)] }
        var table = [0.0]
        var last = piece.p0, along = 0.0
        for k in 1...samples {
            let p = piece.point(at: Double(k) / Double(samples))
            along += hypot(p.x - last.x, p.y - last.y)
            table.append(along)
            last = p
        }
        return table
    }

    /// The curve's parameter at `length` along it, from its table.
    static func parameter(at length: Double, table: [Double]) -> Double {
        let steps = table.count - 1
        guard let total = table.last, total > 0 else { return 0 }
        if length <= 0 { return 0 }
        if length >= total { return 1 }
        var k = 1
        while k < steps && table[k] < length { k += 1 }
        let span = table[k] - table[k - 1]
        let f = span > 0 ? (length - table[k - 1]) / span : 0
        return (Double(k - 1) + f) / Double(steps)
    }

    /// The stretch of a piece between two lengths along it.
    static func trimmed(_ piece: Piece, table: [Double], from start: Double, to end: Double) -> Piece {
        guard start > 0 || end < table.last! else { return piece }
        if piece.isStraight {
            let total = table.last!
            func at(_ l: Double) -> Vec2 {
                let f = total > 0 ? l / total : 0
                return Vec2(piece.p0.x + (piece.p1.x - piece.p0.x) * f, piece.p0.y + (piece.p1.y - piece.p0.y) * f)
            }
            let p0 = at(start), p1 = at(end)
            return Piece(p0: p0, c1: p0, c2: p1, p1: p1, isStraight: true)
        }
        let t0 = parameter(at: start, table: table), t1 = parameter(at: end, table: table)
        let left = split(piece, at: t1).left
        return t1 > 0 ? split(left, at: t0 / t1).right : left
    }

    /// De Casteljau's cut of a cubic at `t`.
    static func split(_ p: Piece, at t: Double) -> (left: Piece, right: Piece) {
        func mix(_ a: Vec2, _ b: Vec2) -> Vec2 { Vec2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }
        let ab = mix(p.p0, p.c1), bc = mix(p.c1, p.c2), cd = mix(p.c2, p.p1)
        let abc = mix(ab, bc), bcd = mix(bc, cd), mid = mix(abc, bcd)
        return (Piece(p0: p.p0, c1: ab, c2: abc, p1: mid, isStraight: false),
                Piece(p0: mid, c1: bcd, c2: cd, p1: p.p1, isStraight: false))
    }
}
