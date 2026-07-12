import Foundation

public enum MiddleClickInputUpdate: Equatable, Sendable {
    case frame(
        generation: UInt64,
        sequence: UInt64,
        timestamp: Double,
        receivedAt: Double,
        touches: [PhysicalTouch]
    )
    case empty(
        generation: UInt64,
        sequence: UInt64,
        timestamp: Double,
        receivedAt: Double
    )
    case cancel(
        generation: UInt64,
        sequence: UInt64,
        receivedAt: Double,
        reason: MiddleClickCancellationReason
    )
}

public enum MiddleClickCancellationReason: Equatable, Sendable {
    case missingBuffer
    case invalidTouchCount
    case monitorStopped
    case pipelineReconfigured
    case permissionLost
    case systemSleep
}

public enum MiddleClickTerminalReason: Equatable, Sendable {
    case completed
    case invalidated
    case cancelled(MiddleClickCancellationReason)
}

public struct MiddleClickTouchUpdate: Equatable, Sendable {
    public let sessionID: UInt64?
    public let chordActive: Bool
    public let tapCandidate: Bool
    public let generation: UInt64
    public let sequence: UInt64
    public let receivedAt: Double
    public let terminalReason: MiddleClickTerminalReason?

    public init(
        sessionID: UInt64?,
        chordActive: Bool,
        tapCandidate: Bool,
        generation: UInt64,
        sequence: UInt64,
        receivedAt: Double,
        terminalReason: MiddleClickTerminalReason?
    ) {
        self.sessionID = sessionID
        self.chordActive = chordActive
        self.tapCandidate = tapCandidate
        self.generation = generation
        self.sequence = sequence
        self.receivedAt = receivedAt
        self.terminalReason = terminalReason
    }
}

public struct MiddleClickRecognizer: Sendable {
    private static let exactTouchCount = 3
    private static let maximumDuration = 0.30
    private static let maximumCentroidMovement = 0.05

    private struct Point: Sendable {
        let x: Double
        let y: Double
    }

    private struct Session: Sendable {
        let id: UInt64
        let startedAt: Double
        var lastTimestamp: Double
        var qualifiedIDs: Set<Int>?
        var initialCentroid: Point?
        var maximumMovement = 0.0
        var releaseStarted = false
        var tapInvalidated = false
        var chordInvalidated = false
        var lastTouchCount = 0

        var chordActive: Bool {
            qualifiedIDs != nil && !releaseStarted && !chordInvalidated
        }
    }

    private let tapEnabled: Bool
    private var nextSessionID: UInt64 = 1
    private var session: Session?

    public init(tapEnabled: Bool) {
        self.tapEnabled = tapEnabled
    }

    public mutating func process(_ update: MiddleClickInputUpdate) -> MiddleClickTouchUpdate {
        switch update {
        case .frame(let generation, let sequence, let timestamp, let receivedAt, let touches):
            guard !touches.isEmpty else {
                return finishSession(
                    generation: generation,
                    sequence: sequence,
                    timestamp: timestamp,
                    receivedAt: receivedAt
                )
            }
            return processFrame(
                generation: generation,
                sequence: sequence,
                timestamp: timestamp,
                receivedAt: receivedAt,
                touches: touches
            )

        case .empty(let generation, let sequence, let timestamp, let receivedAt):
            return finishSession(
                generation: generation,
                sequence: sequence,
                timestamp: timestamp,
                receivedAt: receivedAt
            )

        case .cancel(let generation, let sequence, let receivedAt, let reason):
            let sessionID = session?.id
            session = nil
            return output(
                sessionID: sessionID,
                chordActive: false,
                tapCandidate: false,
                generation: generation,
                sequence: sequence,
                receivedAt: receivedAt,
                terminalReason: .cancelled(reason)
            )
        }
    }

    private mutating func processFrame(
        generation: UInt64,
        sequence: UInt64,
        timestamp: Double,
        receivedAt: Double,
        touches: [PhysicalTouch]
    ) -> MiddleClickTouchUpdate {
        if session == nil {
            session = Session(id: nextSessionID, startedAt: timestamp, lastTimestamp: timestamp)
            nextSessionID &+= 1
        } else if timestamp <= session!.lastTimestamp {
            session!.tapInvalidated = true
        } else {
            session!.lastTimestamp = timestamp
        }

        updateSession(with: touches)

        return output(
            sessionID: session!.id,
            chordActive: session!.chordActive,
            tapCandidate: false,
            generation: generation,
            sequence: sequence,
            receivedAt: receivedAt,
            terminalReason: nil
        )
    }

    private mutating func updateSession(with touches: [PhysicalTouch]) {
        defer { session!.lastTouchCount = touches.count }

        guard touches.count <= Self.exactTouchCount else {
            session!.tapInvalidated = true
            session!.chordInvalidated = true
            return
        }

        guard touches.count == Self.exactTouchCount else {
            if session!.qualifiedIDs != nil {
                if session!.releaseStarted && touches.count > session!.lastTouchCount {
                    session!.tapInvalidated = true
                }
                session!.releaseStarted = true
            }
            return
        }

        guard !session!.releaseStarted else {
            session!.tapInvalidated = true
            session!.chordInvalidated = true
            return
        }

        let ids = Set(touches.map(\.id))
        guard ids.count == Self.exactTouchCount else {
            session!.tapInvalidated = true
            session!.chordInvalidated = true
            return
        }

        let currentCentroid = centroid(of: touches)
        if let qualifiedIDs = session!.qualifiedIDs {
            guard ids == qualifiedIDs else {
                session!.tapInvalidated = true
                session!.chordInvalidated = true
                return
            }

            let initialCentroid = session!.initialCentroid!
            let movement = hypot(
                currentCentroid.x - initialCentroid.x,
                currentCentroid.y - initialCentroid.y
            )
            session!.maximumMovement = max(session!.maximumMovement, movement)
            if session!.maximumMovement > Self.maximumCentroidMovement {
                session!.tapInvalidated = true
            }
        } else if !session!.chordInvalidated {
            session!.qualifiedIDs = ids
            session!.initialCentroid = currentCentroid
        }
    }

    private mutating func finishSession(
        generation: UInt64,
        sequence: UInt64,
        timestamp: Double,
        receivedAt: Double
    ) -> MiddleClickTouchUpdate {
        guard var finishedSession = session else {
            return output(
                sessionID: nil,
                chordActive: false,
                tapCandidate: false,
                generation: generation,
                sequence: sequence,
                receivedAt: receivedAt,
                terminalReason: nil
            )
        }
        session = nil

        if timestamp <= finishedSession.lastTimestamp {
            finishedSession.tapInvalidated = true
        }

        let duration = timestamp - finishedSession.startedAt
        let completed = finishedSession.qualifiedIDs != nil
            && !finishedSession.tapInvalidated
            && !finishedSession.chordInvalidated
            && duration <= Self.maximumDuration
            && finishedSession.maximumMovement <= Self.maximumCentroidMovement

        return output(
            sessionID: finishedSession.id,
            chordActive: false,
            tapCandidate: tapEnabled && completed,
            generation: generation,
            sequence: sequence,
            receivedAt: receivedAt,
            terminalReason: completed ? .completed : .invalidated
        )
    }

    private func centroid(of touches: [PhysicalTouch]) -> Point {
        guard let anchor = touches.first else { return Point(x: 0, y: 0) }
        let delta = touches.dropFirst().reduce(into: (x: 0.0, y: 0.0)) { partial, touch in
            partial.x += touch.x - anchor.x
            partial.y += touch.y - anchor.y
        }
        let count = Double(touches.count)
        return Point(x: anchor.x + delta.x / count, y: anchor.y + delta.y / count)
    }

    private func output(
        sessionID: UInt64?,
        chordActive: Bool,
        tapCandidate: Bool,
        generation: UInt64,
        sequence: UInt64,
        receivedAt: Double,
        terminalReason: MiddleClickTerminalReason?
    ) -> MiddleClickTouchUpdate {
        MiddleClickTouchUpdate(
            sessionID: sessionID,
            chordActive: chordActive,
            tapCandidate: tapCandidate,
            generation: generation,
            sequence: sequence,
            receivedAt: receivedAt,
            terminalReason: terminalReason
        )
    }
}
