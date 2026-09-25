import Foundation
import MotionEvaluation

/// Anything that can draw a `ResolvedScene`.
///
/// The canvas and every offscreen render go through this, so what is drawn on
/// screen and what is exported cannot come from different code. A Metal
/// renderer can be added later as a second conformance without changing
/// anything that calls it.
///
/// A renderer is used from one thread at a time. The canvas's lives on the
/// main thread; an export makes its own.
public protocol SceneRenderer: AnyObject {
    /// Draws `scene`, replacing whatever was drawn before. Nothing animates
    /// between one call and the next: each scene is drawn exactly as given.
    func render(_ scene: ResolvedScene)
}
