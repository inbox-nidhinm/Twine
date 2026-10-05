import AppKit
import SwiftUI

/// The app's one window. It shows the home screen or a project's editor,
/// never both and never two: opening a project turns the home screen into
/// the editor, and Home turns it back, saving and closing the project. A
/// project opened from the Finder while another is open takes its place.
///
/// AppKit's documents each want a window controller, so the window is handed
/// from controller to controller: `take()` frees it from whichever has it
/// (closing that project once it has saved) and `present(_:in:)` fades the
/// new content in. Closing the window quits, as closing the home window did.
@MainActor
enum MainWindow {
    /// The smallest the window goes, for the home screen and the editor alike
    /// (5 October 2026, raised from 980 by 660): room for the editor's two
    /// panels, a canvas and the timeline, and for Settings' two columns.
    static let minimum = NSSize(width: 1200, height: 760)

    static let window: ChromelessWindow = {
        let window = makeChromelessWindow(size: NSSize(width: 1440, height: 920), minSize: minimum)
        // It is kept for the app's whole life and handed between controllers.
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("Main")
        return window
    }()

    /// The window, freed from the controller showing it. A project there is
    /// saved and closed; `then` runs once it has.
    static func take(then: @escaping () -> Void = {}) -> ChromelessWindow {
        switch window.windowController {
        case let editor as EditorWindowController:
            editor.leave(then: then)
        case let other?:
            other.window = nil
            then()
        case nil:
            then()
        }
        window.windowController = nil
        window.delegate = nil
        return window
    }

    /// Puts `content` in the window with a short fade, and the window's
    /// buttons back where they belong.
    /// The content never sizes the window: a SwiftUI host would otherwise
    /// set the window's smallest to its own (the editor's let it shrink to
    /// half the width, and kept doing so on the home screen after) or grow
    /// it to fit (the home screen did, with every folder).
    static func present(_ content: NSView, in window: ChromelessWindow) {
        if let host = content as? any HostingSizing { host.sizesNothing() }
        content.wantsLayer = true
        content.alphaValue = 0
        window.contentView = content
        // The window keeps to its `sizeFloor` whatever the content says.
        window.sizeFloor = minimum
        // A window saved smaller than that grows to it, on its screen.
        var frame = window.frame
        if frame.width < minimum.width || frame.height < minimum.height {
            frame.size = NSSize(width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
            if let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                frame.origin.x = min(max(frame.minX, visible.minX), max(visible.maxX - frame.width, visible.minX))
                frame.origin.y = min(max(frame.minY, visible.minY), max(visible.maxY - frame.height, visible.minY))
            }
            window.setFrame(frame, display: false)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            content.animator().alphaValue = 1
        }
        window.clearInitialFocus()
        TrafficLights.retry(in: window)
    }
}

/// A SwiftUI host that can be told to leave the window's size alone.
@MainActor
protocol HostingSizing {
    func sizesNothing()
}

extension NSHostingView: HostingSizing {
    func sizesNothing() { sizingOptions = [] }
}
