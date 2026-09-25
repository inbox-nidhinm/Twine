import SwiftUI

/// Draws an `Icon` as a stroked vector path.
///
/// The artwork is stroke-based on a 24-unit grid, so the stroke scales with the
/// box: a 36pt tool gets a proportionally heavier line than a 16pt glyph.
/// `strokedPath` turns the stroke into an outline, and a `Shape` used as a view
/// fills itself with the current `foregroundStyle`, so these tint exactly the
/// way SF Symbols do.
public struct IconShape: Shape {
    public let icon: Icon
    /// On the artwork's own 24-unit grid, matching the source SVGs.
    public var lineWidth: CGFloat

    public init(icon: Icon, lineWidth: CGFloat = 1.5) {
        self.icon = icon
        self.lineWidth = lineWidth
    }

    public func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / IconPath.grid
        let centred = CGAffineTransform(
            translationX: rect.minX + (rect.width - IconPath.grid * scale) / 2,
            y: rect.minY + (rect.height - IconPath.grid * scale) / 2
        ).scaledBy(x: scale, y: scale)

        return IconPath.path(for: icon)
            .applying(centred)
            .strokedPath(StrokeStyle(lineWidth: lineWidth * scale, lineCap: .round, lineJoin: .round))
    }
}

/// An icon at a given box size. The size is the grid's edge, not a font size.
public struct IconView: View {
    public let icon: Icon
    public var size: CGFloat
    public var lineWidth: CGFloat

    public init(_ icon: Icon, size: CGFloat = Theme.icon, lineWidth: CGFloat = 1.5) {
        self.icon = icon
        self.size = size
        self.lineWidth = lineWidth
    }

    public var body: some View {
        IconShape(icon: icon, lineWidth: lineWidth)
            .frame(width: size, height: size)
    }
}

// MARK: - Path data

enum IconPath {
    static let grid: CGFloat = 24

    /// Parsed once per icon and kept. The panels rebuild on every selection
    /// change and there is no reason to parse again.
    @MainActor private static var cache: [Icon: Path] = [:]

    static func path(for icon: Icon) -> Path {
        // `Shape.path(in:)` is not main-actor isolated, but SwiftUI only calls
        // it from the main thread. Anywhere else, parse without the cache.
        guard Thread.isMainThread else { return parse(icon) }
        return MainActor.assumeIsolated {
            if let hit = cache[icon] { return hit }
            let path = parse(icon)
            cache[icon] = path
            return path
        }
    }

    private static func parse(_ icon: Icon) -> Path {
        var path = Path()
        for d in icon.data { append(d, to: &path) }
        return path
    }

    /// A parser for the subset icon artwork uses: `M L H V C Z`, in either
    /// case, with implicit repeats. `svg_to_swift.py` refuses to emit anything
    /// else, so an unsupported command cannot reach this. Extend both together.
    private static func append(_ d: String, to path: inout Path) {
        var numbers: [CGFloat] = []
        var command: Character = " "
        var start = CGPoint.zero
        var pen = CGPoint.zero

        func flush() {
            var i = 0
            func next() -> CGFloat { defer { i += 1 }; return i < numbers.count ? numbers[i] : 0 }
            let relative = command.isLowercase

            switch Character(command.uppercased()) {
            case "M":
                // A second pair after an M is an implicit lineTo, per the spec.
                var first = true
                while i < numbers.count {
                    let p = point(next(), next(), relative: relative, from: pen)
                    if first { path.move(to: p); start = p; first = false } else { path.addLine(to: p) }
                    pen = p
                }
            case "L":
                while i < numbers.count {
                    let p = point(next(), next(), relative: relative, from: pen)
                    path.addLine(to: p)
                    pen = p
                }
            case "H":
                while i < numbers.count {
                    let x = next()
                    pen = CGPoint(x: relative ? pen.x + x : x, y: pen.y)
                    path.addLine(to: pen)
                }
            case "V":
                while i < numbers.count {
                    let y = next()
                    pen = CGPoint(x: pen.x, y: relative ? pen.y + y : y)
                    path.addLine(to: pen)
                }
            case "C":
                while i + 5 < numbers.count {
                    let c1 = point(next(), next(), relative: relative, from: pen)
                    let c2 = point(next(), next(), relative: relative, from: pen)
                    let to = point(next(), next(), relative: relative, from: pen)
                    path.addCurve(to: to, control1: c1, control2: c2)
                    pen = to
                }
            case "Z":
                path.closeSubpath()
                pen = start
            default:
                break
            }
            numbers.removeAll(keepingCapacity: true)
        }

        var number = ""
        func takeNumber() {
            if !number.isEmpty, let v = Double(number) { numbers.append(CGFloat(v)) }
            number = ""
        }

        for ch in d {
            if ch.isLetter && ch != "e" && ch != "E" {
                takeNumber()
                if command != " " { flush() }
                command = ch
            } else if ch == "," || ch == " " || ch == "\n" || ch == "\t" {
                takeNumber()
            } else if ch == "-" && !number.isEmpty && !number.hasSuffix("e") && !number.hasSuffix("E") {
                // A minus with digits already banked starts the next number.
                takeNumber()
                number = "-"
            } else if ch == "." && number.contains(".") {
                // "1.5.5" is two numbers, which is legal SVG shorthand.
                takeNumber()
                number = "."
            } else {
                number.append(ch)
            }
        }
        takeNumber()
        if command != " " { flush() }
    }

    private static func point(_ x: CGFloat, _ y: CGFloat, relative: Bool, from pen: CGPoint) -> CGPoint {
        relative ? CGPoint(x: pen.x + x, y: pen.y + y) : CGPoint(x: x, y: y)
    }
}
