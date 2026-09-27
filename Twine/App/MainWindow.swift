import AppKit

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
    static let window: ChromelessWindow = {
        let window = makeChromelessWindow(size: NSSize(width: 1440, height: 920), minSize: NSSize(width: 980, height: 660))
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
    static func present(_ content: NSView, in window: ChromelessWindow) {
        content.wantsLayer = true
        content.alphaValue = 0
        window.contentView = content
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            content.animator().alphaValue = 1
        }
        window.clearInitialFocus()
        TrafficLights.retry(in: window)
    }
}
