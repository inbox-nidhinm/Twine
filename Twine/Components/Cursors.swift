import AppKit
import ObjectiveC

/// The app's own pointers, drawn as 32 by 32 point SVGs in
/// `Resources/Cursors`. Each falls back to the nearest system cursor if its
/// file is ever missing, so a pointer never disappears.
///
/// The arrow replaces the system's everywhere in the app: panels, timeline,
/// home and canvas alike, so the pointer never changes style as it moves.
/// Text fields keep the I-beam. The resize, turn, hand and pen pointers are
/// used wherever those things happen.
enum Cursors {
    /// Makes the app's arrow the one every part of the app gets when it asks
    /// for the arrow, SwiftUI and AppKit included, by swapping what
    /// `NSCursor.arrow` returns. SwiftUI sets the arrow over its views on
    /// every move, which no cursor rect can overrule, so this is the only
    /// way the pointer keeps one style. Call once, at launch, before any
    /// window.
    static func useAppArrowEverywhere() {
        // Built first, while `.arrow` is still the system's, for its fallback.
        let mine = arrow
        guard mine !== NSCursor.arrow,
              let original = class_getClassMethod(NSCursor.self, #selector(getter: NSCursor.arrow)),
              let replacement = class_getClassMethod(NSCursor.self, #selector(NSCursor.twineArrow)) else { return }
        NSCursor.appArrow = mine
        method_exchangeImplementations(original, replacement)
    }

    static let arrow = make("cursor-arrow", hotSpot: CGPoint(x: 11.5, y: 11.5), fallback: .arrow)
    static let crosshair = make("cursor-shape", fallback: .crosshair)
    static let hand = make("cursor-hand", fallback: .openHand)
    static let handGrabbed = make("cursor-hand-grabbed", fallback: .closedHand)
    static let resizeHorizontal = make("cursor-resize-horizontal", fallback: .resizeLeftRight)
    static let resizeVertical = make("cursor-resize-vertical", fallback: .resizeUpDown)
    static let resizeNWSE = make("cursor-resize-nwse", fallback: .frameResize(position: .topLeft, directions: .all))
    static let resizeNESW = make("cursor-resize-nesw", fallback: .frameResize(position: .topRight, directions: .all))
    /// Arrows every way: over a gradient's handles, its stops and its line,
    /// and while they are dragged (the designer's, 5 October 2026).
    static let moveAll = make("cursor-move-all", fallback: .openHand)
    static let rotateTopLeft = make("cursor-rotate-top-left", fallback: .crosshair)
    static let rotateTopRight = make("cursor-rotate-top-right", fallback: .crosshair)
    static let rotateBottomLeft = make("cursor-rotate-bottom-left", fallback: .crosshair)
    static let rotateBottomRight = make("cursor-rotate-bottom-right", fallback: .crosshair)
    /// The pen, with its nib at the hot spot: plain for placing a point, and
    /// with a mark for adding a point on a segment, moving a point, and
    /// joining onto an end.
    static let pen = make("cursor-pen", hotSpot: penTip, fallback: .crosshair)
    static let penAdd = make("cursor-pen-add", hotSpot: penTip, fallback: .crosshair)
    static let penMove = make("cursor-pen-move", hotSpot: penTip, fallback: .crosshair)
    static let penConnect = make("cursor-pen-connect", hotSpot: penTip, fallback: .crosshair)
    private static let penTip = CGPoint(x: 11, y: 10)

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

extension NSCursor {
    /// The cursor `NSCursor.arrow` hands out once `Cursors.useAppArrowEverywhere`
    /// has run. Set once at launch, on the main thread, before anything reads it.
    nonisolated(unsafe) fileprivate static var appArrow: NSCursor?

    @objc nonisolated fileprivate class func twineArrow() -> NSCursor {
        // After the swap this runs as `NSCursor.arrow`, and the name
        // `twineArrow` runs the system's original.
        appArrow ?? twineArrow()
    }
}
