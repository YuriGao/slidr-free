import Foundation

public enum NormalizedInputEvent: Equatable, Sendable {
    case physicalTouchFrame(touches: [PhysicalTouch], timestamp: Double)
    case middleClick(x: Double, y: Double, timestamp: Double)

    public static func == (lhs: NormalizedInputEvent, rhs: NormalizedInputEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.physicalTouchFrame(lhsTouches, lhsTimestamp), .physicalTouchFrame(rhsTouches, rhsTimestamp)):
            return lhsTouches == rhsTouches && lhsTimestamp == rhsTimestamp
        case let (.middleClick(lhsX, lhsY, lhsTimestamp), .middleClick(rhsX, rhsY, rhsTimestamp)):
            return lhsX == rhsX && lhsY == rhsY && lhsTimestamp == rhsTimestamp
        default:
            return false
        }
    }
}
