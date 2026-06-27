import Foundation

public enum NormalizedInputEvent: Equatable, Sendable {
    case scroll(x: Double, y: Double, deltaY: Double, timestamp: Double, screenSize: CGSize)
    case keyDown(timestamp: Double)
    case middleClick(x: Double, y: Double, timestamp: Double)

    public static func == (lhs: NormalizedInputEvent, rhs: NormalizedInputEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.scroll(lhsX, lhsY, lhsDeltaY, lhsTimestamp, lhsScreenSize), .scroll(rhsX, rhsY, rhsDeltaY, rhsTimestamp, rhsScreenSize)):
            return lhsX == rhsX
                && lhsY == rhsY
                && lhsDeltaY == rhsDeltaY
                && lhsTimestamp == rhsTimestamp
                && lhsScreenSize.width == rhsScreenSize.width
                && lhsScreenSize.height == rhsScreenSize.height
        case let (.keyDown(lhsTimestamp), .keyDown(rhsTimestamp)):
            return lhsTimestamp == rhsTimestamp
        case let (.middleClick(lhsX, lhsY, lhsTimestamp), .middleClick(rhsX, rhsY, rhsTimestamp)):
            return lhsX == rhsX && lhsY == rhsY && lhsTimestamp == rhsTimestamp
        default:
            return false
        }
    }
}
