import Foundation

public enum NormalizedInputEvent: Equatable, Sendable {
    case physicalTouchFrame(touches: [PhysicalTouch], timestamp: Double)
}
