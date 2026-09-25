import Foundation

/// Every value an action can hold. The model only promises that values can be
/// stored and compared; how two of them blend is the evaluation layer's job, so
/// interpolation lives there and not here.
public protocol AnimatableValue: Codable, Sendable, Equatable {}

extension Double: AnimatableValue {}
extension Array: AnimatableValue where Element: AnimatableValue {}

/// A point or an offset in pixels. Composition space runs from the top-left
/// corner with y pointing down, the same as Figma, so a future importer can copy
/// coordinates across without flipping them.
public struct Vec2: AnimatableValue, Hashable {
    public var x: Double
    public var y: Double

    public init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = Vec2(0, 0)
    public static let one = Vec2(1, 1)

    public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
}

/// A width and height in pixels.
public struct Size2: AnimatableValue, Hashable {
    public var width: Double
    public var height: Double

    public init(_ width: Double, _ height: Double) {
        self.width = width
        self.height = height
    }

    public var center: Vec2 { Vec2(width / 2, height / 2) }
}

/// A colour in sRGB, each channel 0 to 1, not premultiplied.
public struct RGBA: AnimatableValue, Hashable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public static let white = RGBA(1, 1, 1)
    public static let black = RGBA(0, 0, 0)
    public static let clear = RGBA(0, 0, 0, 0)

    /// `#RRGGBB` or `#RRGGBBAA`, with or without the hash.
    public init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6 || text.count == 8, let value = UInt64(text, radix: 16) else { return nil }
        let hasAlpha = text.count == 8
        let v = hasAlpha ? value : (value << 8) | 0xFF
        self.init(Double((v >> 24) & 0xFF) / 255,
                  Double((v >> 16) & 0xFF) / 255,
                  Double((v >> 8) & 0xFF) / 255,
                  Double(v & 0xFF) / 255)
    }

    /// Six digits, upper case, no hash. Alpha is shown separately in the UI.
    public var hex6: String {
        func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}

/// One radius per corner, clockwise from the top-left, in pixels.
public struct CornerRadii: AnimatableValue, Hashable {
    public var topLeft: Double
    public var topRight: Double
    public var bottomRight: Double
    public var bottomLeft: Double

    public init(topLeft: Double, topRight: Double, bottomRight: Double, bottomLeft: Double) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
        self.bottomLeft = bottomLeft
    }

    public init(all radius: Double) {
        self.init(topLeft: radius, topRight: radius, bottomRight: radius, bottomLeft: radius)
    }

    public static let zero = CornerRadii(all: 0)

    public var isUniform: Bool {
        topLeft == topRight && topRight == bottomRight && bottomRight == bottomLeft
    }
}
