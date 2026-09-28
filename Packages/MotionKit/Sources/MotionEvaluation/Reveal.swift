import Foundation
import MotionModel

/// How much of a layer shows through a clip of its own box, as the Mask
/// presets draw it: the part of the box that shows, and how the layer's
/// content sits behind it. Every amount is a fraction of the box, so a
/// preset suits a layer of any size. The whole box with nothing moved is
/// `full`: no clip at all.
public struct RevealBox: AnimatableValue, Interpolatable {
    /// The part of the box that shows: its left, top, width and height.
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    /// How far the content sits from its place behind the clip.
    public var dx: Double
    public var dy: Double
    /// How big the content is behind the clip, about the box's centre.
    public var zoom: Double

    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1,
                dx: Double = 0, dy: Double = 0, zoom: Double = 1) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.dx = dx
        self.dy = dy
        self.zoom = zoom
    }

    public static let full = RevealBox()

    /// The content moved a whole box away toward `direction`, so the clip
    /// shows none of it.
    public static func away(_ direction: PresetDirection) -> RevealBox {
        switch direction {
        case .left: RevealBox(dx: -1)
        case .right: RevealBox(dx: 1)
        case .top: RevealBox(dy: -1)
        case .bottom: RevealBox(dy: 1)
        }
    }

    /// Nothing open yet, at the edge on `side`: a clip that opens from
    /// there grows across the box.
    public static func edge(_ side: PresetDirection) -> RevealBox {
        switch side {
        case .left: RevealBox(width: 0)
        case .right: RevealBox(x: 1, width: 0)
        case .top: RevealBox(height: 0)
        case .bottom: RevealBox(y: 1, height: 0)
        }
    }

    /// Nothing open yet, along the upright line through the middle.
    public static let middle = RevealBox(x: 0.5, width: 0)

    /// Nothing open yet, at the very centre, with the content at `zoom`.
    public static func centre(zoom: Double) -> RevealBox {
        RevealBox(x: 0.5, y: 0.5, width: 0, height: 0, zoom: zoom)
    }

    /// Whether the clip shows nothing: it is shut, or the content has moved
    /// wholly out of it.
    public var showsNothing: Bool {
        if width <= 1e-9 || height <= 1e-9 || zoom <= 1e-9 { return true }
        // The content's box, moved and zoomed, against the clip.
        let left = 0.5 + dx - zoom / 2, right = 0.5 + dx + zoom / 2
        let top = 0.5 + dy - zoom / 2, bottom = 0.5 + dy + zoom / 2
        return right <= x + 1e-9 || left >= x + width - 1e-9 || bottom <= y + 1e-9 || top >= y + height - 1e-9
    }

    public static func interpolate(_ a: RevealBox, _ b: RevealBox, _ t: Double) -> RevealBox {
        RevealBox(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t),
                  width: max(lerp(a.width, b.width, t), 0), height: max(lerp(a.height, b.height, t), 0),
                  dx: lerp(a.dx, b.dx, t), dy: lerp(a.dy, b.dy, t), zoom: max(lerp(a.zoom, b.zoom, t), 0))
    }
}

/// A layer's reveal, kept out of line as `Warp` is: almost no layer has one,
/// and every number carried in a layer's state costs every frame.
public enum Reveal: Sendable, Equatable {
    case none
    indirect case clipped(RevealBox)

    /// `.none` for the whole box with nothing moved, which needs no clip.
    public init(_ box: RevealBox) {
        let f = RevealBox.full
        let near = { (a: Double, b: Double) in abs(a - b) < 1e-6 }
        self = near(box.x, f.x) && near(box.y, f.y) && near(box.width, f.width) && near(box.height, f.height)
            && near(box.dx, f.dx) && near(box.dy, f.dy) && near(box.zoom, f.zoom) ? .none : .clipped(box)
    }

    public var box: RevealBox {
        if case .clipped(let b) = self { return b }
        return .full
    }

    public var showsNothing: Bool {
        if case .clipped(let b) = self { return b.showsNothing }
        return false
    }
}
