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
    public static let defaultMaximumInterTapInterval = 0.75
    public static let defaultMaximumMovement = 0.03

    private static let maximumTapDuration = 0.45
    private static let timestampComparisonTolerance = 1e-9
    // The app supplies the user-configured interval while the core recognizer
    // remains independent of persistence and UI concerns.
    private let maximumInterTapInterval: Double
    private let maximumMovement: Double

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

    public var isTrackingCandidate: Bool {
        if case .candidate = activeContact { return true }
        return false
    }

    public init(
        maximumInterTapInterval: Double = Self.defaultMaximumInterTapInterval,
        maximumMovement: Double = Self.defaultMaximumMovement
    ) {
        self.maximumInterTapInterval = Self.validatedInterTapInterval(maximumInterTapInterval)
        self.maximumMovement = Self.validatedMovement(maximumMovement)
    }

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
            // Once a possible second tap has started, its start time owns the
            // inter-tap decision. Do not expire the first tap while that second
            // contact is still being evaluated.
            if activeContact == nil {
                expireFirstTapIfNeeded(at: timestamp)
            }
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
              hypot(touch.x - session.initialX, touch.y - session.initialY) <= maximumMovement else {
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
           isWithinInterTapInterval(session.startedAt - firstTap.endedAt) {
            self.firstTap = nil
            return session.corner
        }

        firstTap = CompletedTap(corner: session.corner, endedAt: timestamp)
        return nil
    }

    private mutating func expireFirstTapIfNeeded(at timestamp: Double) {
        guard let firstTap,
              !isWithinInterTapInterval(timestamp - firstTap.endedAt) else { return }
        self.firstTap = nil
    }

    private func isWithinInterTapInterval(_ elapsed: Double) -> Bool {
        elapsed <= maximumInterTapInterval + Self.timestampComparisonTolerance
    }

    private static func validatedInterTapInterval(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultMaximumInterTapInterval }
        return value
    }

    private static func validatedMovement(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return defaultMaximumMovement }
        return value
    }

}
