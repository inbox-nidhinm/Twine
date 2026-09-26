import AppKit

/// The app's own pointers, drawn as 32 by 32 point SVGs in
/// `Resources/Cursors`. Each falls back to the nearest system cursor if its
/// file is ever missing, so a pointer never disappears.
///
/// The arrow and the crosshair are the canvas's; panels keep the system
/// arrow. The resize, turn and hand pointers are used wherever those things
/// happen, canvas and timeline alike.
enum Cursors {
    static let arrow = make("cursor-arrow", hotSpot: CGPoint(x: 11.5, y: 11.5), fallback: .arrow)
    static let crosshair = make("cursor-shape", fallback: .crosshair)
    static let hand = make("cursor-hand", fallback: .openHand)
    static let handGrabbed = make("cursor-hand-grabbed", fallback: .closedHand)
    static let resizeHorizontal = make("cursor-resize-horizontal", fallback: .resizeLeftRight)
    static let resizeVertical = make("cursor-resize-vertical", fallback: .resizeUpDown)
    static let resizeNWSE = make("cursor-resize-nwse", fallback: .frameResize(position: .topLeft, directions: .all))
    static let resizeNESW = make("cursor-resize-nesw", fallback: .frameResize(position: .topRight, directions: .all))
    static let rotateTopLeft = make("cursor-rotate-top-left", fallback: .crosshair)
    static let rotateTopRight = make("cursor-rotate-top-right", fallback: .crosshair)
    static let rotateBottomLeft = make("cursor-rotate-bottom-left", fallback: .crosshair)
    static let rotateBottomRight = make("cursor-rotate-bottom-right", fallback: .crosshair)

    /// The resize pointer for a handle lying in `direction` from the middle
    /// of its box, on screen, so a turned layer gets arrows that follow it.
    static func resize(toward direction: CGVector) -> NSCursor {
        // The angle folded into half a turn: 0 is across, 90 is up and down.
        var degrees = atan2(direction.dy, direction.dx) * 180 / .pi
        if degrees < 0 { degrees += 180 }
        switch degrees {
        case ..<22.5, 157.5...: return resizeHorizontal
        case 67.5..<112.5: return resizeVertical
        // The view runs downward, so a positive angle points down and right.
        case 22.5..<67.5: return resizeNWSE
        default: return resizeNESW
        }
    }

    /// The turn pointer for a corner lying in `direction` from the middle of
    /// its box, on screen, curling round that corner.
    static func rotate(toward direction: CGVector) -> NSCursor {
        switch (direction.dx < 0, direction.dy < 0) {
        case (true, true): return rotateTopLeft
        case (false, true): return rotateTopRight
        case (true, false): return rotateBottomLeft
        case (false, false): return rotateBottomRight
        }
    }

    private static func make(_ name: String, hotSpot: CGPoint = CGPoint(x: 16, y: 16), fallback: NSCursor) -> NSCursor {
        let url = Bundle.main.url(forResource: name, withExtension: "svg")
            ?? Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "Cursors")
        guard let url, let image = NSImage(contentsOf: url) else { return fallback }
        image.size = NSSize(width: 32, height: 32)
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}
