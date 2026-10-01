import Foundation
import MotionModel

/// How far a layer has curled away from `corner`, as the Page Curl presets
/// draw it: 0 is flat, 1 is curled right off.
public struct PageCurl: AnimatableValue, Interpolatable {
    public var progress: Double
    public var corner: PresetCorner

    public init(progress: Double, corner: PresetCorner) {
        self.progress = progress
        self.corner = corner
    }

    public static let flat = PageCurl(progress: 0, corner: .topRight)

    /// The corner is the curling end's: a flat end has none of its own.
    public static func interpolate(_ a: PageCurl, _ b: PageCurl, _ t: Double) -> PageCurl {
        PageCurl(progress: min(max(lerp(a.progress, b.progress, t), 0), 1),
                 corner: b.progress > 0 || a.progress == 0 ? b.corner : a.corner)
    }
}

/// A layer's curl, kept out of line as `Reveal` is: almost no layer has one.
public enum Curl: Sendable, Equatable {
    case none
    indirect case curled(PageCurl)

    /// `.none` while flat. A layer curled right off draws nothing, which
    /// `resolve` makes a fade to nothing.
    public init(_ curl: PageCurl) {
        self = curl.progress <= 1e-6 ? .none : .curled(curl)
    }

    public var curl: PageCurl {
        if case .curled(let c) = self { return c }
        return .flat
    }

    public var isGone: Bool { curl.progress >= 1 - 1e-6 }
}
