import Foundation
import MotionModel

/// How far a stroke's dashes have travelled along its path, in pixels, from
/// its Dash actions (forward, towards the path's end, is positive), and
/// whether they travel the way its trim draws rather than along the path.
public struct DashTravel: AnimatableValue {
    public var distance: Double
    public var followsTrim: Bool

    public init(distance: Double, followsTrim: Bool) {
        self.distance = distance
        self.followsTrim = followsTrim
    }

    public static let still = DashTravel(distance: 0, followsTrim: false)
}
