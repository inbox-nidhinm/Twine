import AppKit

/// The AppKit app lifecycle rather than SwiftUI's `App`: eMotion's documents
/// are `NSDocument`s, which SwiftUI's document scenes do not host, and an
/// AppKit main menu validates itself against the responder chain for free.
/// Every window's content is still SwiftUI.
@main
enum EMotionMain {
    static func main() {
        let app = NSApplication.shared
        // The first document controller created becomes the shared one, so
        // this has to exist before anything asks for `NSDocumentController.shared`.
        _ = DocumentController()
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
