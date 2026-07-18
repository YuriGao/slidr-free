import Foundation

public enum TrackpadCorner: String, Codable, CaseIterable, Hashable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public static func hit(for touch: PhysicalTouch, widthPercent: Double) -> TrackpadCorner? {
        guard (0...1).contains(touch.x), (0...1).contains(touch.y) else { return nil }
        let width = min(max(widthPercent, 0.04), 0.20)
        let isLeft = touch.x <= width
        let isRight = touch.x >= 1 - width
        let isTop = touch.y >= 1 - width
        let isBottom = touch.y <= width

        switch (isLeft, isRight, isTop, isBottom) {
        case (true, false, true, false): return .topLeft
        case (false, true, true, false): return .topRight
        case (true, false, false, true): return .bottomLeft
        case (false, true, false, true): return .bottomRight
        default: return nil
        }
    }
}

public struct CornerDoubleTapRecognizer: Sendable {
    private static let maximumTapDuration = 0.30
    // Keep this below the minimum configurable edge step distance (0.02) so a
    // qualifying corner tap can never emit an edge adjustment at the same time.
    private static let maximumTapMovement = 0.015
    private static let maximumInterTapInterval = 0.40

    private struct TapSession: Sendable {
        let corner: TrackpadCorner
        let touchID: Int
        let startedAt: Double
        let initialX: Double
        let initialY: Double
        var lastTimestamp: Double
    }

    private struct CompletedTap: Sendable {
        let corner: TrackpadCorner
        let endedAt: Double
    }

    private enum ActiveContact: Sendable {
        case candidate(TapSession)
        case blocked
    }

    private var activeContact: ActiveContact?
    private var firstTap: CompletedTap?

    public init() {}

    public mutating func process(
        _ event: NormalizedInputEvent,
        cornerWidthPercent: Double,
        isEnabled: Bool = true
    ) -> TrackpadCorner? {
        guard isEnabled else {
            reset()
            return nil
        }

        switch event {
        case .physicalTouchCancelled:
            reset()
            return nil

        case .physicalTouchFrame(let touches, let timestamp):
            expireFirstTapIfNeeded(at: timestamp)
            guard !touches.isEmpty else { return finishContact(at: timestamp) }

            if activeContact == nil {
                return beginContact(touches: touches, timestamp: timestamp, cornerWidthPercent: cornerWidthPercent)
            }
            return continueContact(touches: touches, timestamp: timestamp)
        }
    }

    public mutating func reset() {
        activeContact = nil
        firstTap = nil
    }

    private mutating func beginContact(
        touches: [PhysicalTouch],
        timestamp: Double,
        cornerWidthPercent: Double
    ) -> TrackpadCorner? {
        guard touches.count == 1,
              let touch = touches.first,
              let corner = TrackpadCorner.hit(for: touch, widthPercent: cornerWidthPercent) else {
            activeContact = .blocked
            firstTap = nil
            return nil
        }

        if let firstTap,
           firstTap.corner != corner || timestamp <= firstTap.endedAt {
            self.firstTap = nil
        }

        activeContact = .candidate(TapSession(
            corner: corner,
            touchID: touch.id,
            startedAt: timestamp,
            initialX: touch.x,
            initialY: touch.y,
            lastTimestamp: timestamp
        ))
        return nil
    }

    private mutating func continueContact(touches: [PhysicalTouch], timestamp: Double) -> TrackpadCorner? {
        guard case .candidate(var session) = activeContact,
              touches.count == 1,
              let touch = touches.first,
              touch.id == session.touchID,
              timestamp > session.lastTimestamp,
              timestamp - session.startedAt <= Self.maximumTapDuration,
              hypot(touch.x - session.initialX, touch.y - session.initialY) <= Self.maximumTapMovement else {
            activeContact = .blocked
            firstTap = nil
            return nil
        }

        session.lastTimestamp = timestamp
        activeContact = .candidate(session)
        return nil
    }

    private mutating func finishContact(at timestamp: Double) -> TrackpadCorner? {
        guard let activeContact else { return nil }
        self.activeContact = nil

        guard case .candidate(let session) = activeContact,
              timestamp > session.lastTimestamp,
              timestamp - session.startedAt <= Self.maximumTapDuration else {
            firstTap = nil
            return nil
        }

        if let firstTap,
           firstTap.corner == session.corner,
           session.startedAt > firstTap.endedAt,
           session.startedAt - firstTap.endedAt <= Self.maximumInterTapInterval {
            self.firstTap = nil
            return session.corner
        }

        firstTap = CompletedTap(corner: session.corner, endedAt: timestamp)
        return nil
    }

    private mutating func expireFirstTapIfNeeded(at timestamp: Double) {
        guard let firstTap,
              timestamp - firstTap.endedAt > Self.maximumInterTapInterval else { return }
        self.firstTap = nil
    }

}
