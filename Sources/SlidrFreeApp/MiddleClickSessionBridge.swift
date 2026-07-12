import Foundation
import SlidrFreeCore

struct MiddleClickPendingRelease: Equatable, Sendable {
    let sourceButton: Int64
    let eventNumber: Int64
    let generation: UInt64
}

final class MiddleClickSessionBridge: @unchecked Sendable {
    private static let chordFreshness = 0.15

    private struct OpenSession {
        let sessionID: UInt64
        let generation: UInt64
        let chordActive: Bool
        let tapReady: Bool
        let lastReceivedAt: Double
    }

    private enum State {
        case idle
        case open(OpenSession)
        case physicalPending(
            sessionID: UInt64,
            sourceButton: Int64,
            eventNumber: Int64,
            generation: UInt64
        )
        case physicalConsumed(sessionID: UInt64, generation: UInt64)
        case tapClaimed(sessionID: UInt64, generation: UInt64)
        case closed(sessionID: UInt64, generation: UInt64)
    }

    private let lock = NSLock()
    private let now: () -> Double
    private var state: State = .idle
    private var accepting: Bool
    private var currentGeneration: UInt64
    private var lastSequence: UInt64?

    init(
        generation: UInt64,
        accepting: Bool = true,
        now: @escaping () -> Double
    ) {
        currentGeneration = generation
        self.accepting = accepting
        self.now = now
    }

    var generation: UInt64 {
        withLock { currentGeneration }
    }

    func applyTouchUpdate(_ update: MiddleClickTouchUpdate) {
        withLock {
            guard accepting,
                  update.generation == currentGeneration,
                  lastSequence.map({ update.sequence > $0 }) ?? true else {
                return
            }
            lastSequence = update.sequence

            if case .physicalPending = state {
                return
            }

            guard let sessionID = update.sessionID else {
                return
            }

            switch state {
            case .physicalConsumed(let terminalSessionID, let terminalGeneration),
                 .tapClaimed(let terminalSessionID, let terminalGeneration),
                 .closed(let terminalSessionID, let terminalGeneration):
                guard terminalSessionID != sessionID || terminalGeneration != update.generation else {
                    return
                }
            case .idle, .open, .physicalPending:
                break
            }

            if update.chordActive {
                state = .open(
                    OpenSession(
                        sessionID: sessionID,
                        generation: update.generation,
                        chordActive: true,
                        tapReady: false,
                        lastReceivedAt: update.receivedAt
                    )
                )
                return
            }

            if update.tapCandidate, update.terminalReason == .completed {
                state = .open(
                    OpenSession(
                        sessionID: sessionID,
                        generation: update.generation,
                        chordActive: false,
                        tapReady: true,
                        lastReceivedAt: update.receivedAt
                    )
                )
            } else {
                state = .closed(sessionID: sessionID, generation: update.generation)
            }
        }
    }

    func claimTap(sessionID: UInt64, generation: UInt64) -> Bool {
        withLock {
            guard accepting,
                  case .open(let session) = state,
                  session.sessionID == sessionID,
                  session.generation == generation,
                  session.tapReady,
                  !session.chordActive else {
                return false
            }

            state = .tapClaimed(sessionID: sessionID, generation: generation)
            return true
        }
    }

    func beginPhysical(sourceButton: Int64, eventNumber: Int64, generation: UInt64) -> Bool {
        withLock {
            guard accepting,
                  generation == currentGeneration,
                  case .open(let session) = state,
                  session.generation == generation,
                  session.chordActive else {
                return false
            }

            let age = now() - session.lastReceivedAt
            guard age >= 0, age <= Self.chordFreshness else {
                return false
            }

            state = .physicalPending(
                sessionID: session.sessionID,
                sourceButton: sourceButton,
                eventNumber: eventNumber,
                generation: generation
            )
            return true
        }
    }

    func continueDrag(sourceButton: Int64, eventNumber: Int64, generation: UInt64) -> Bool {
        withLock {
            matchesPending(
                sourceButton: sourceButton,
                eventNumber: eventNumber,
                generation: generation
            ) != nil
        }
    }

    func finishPhysical(sourceButton: Int64, eventNumber: Int64, generation: UInt64) -> Bool {
        withLock {
            guard let sessionID = matchesPending(
                sourceButton: sourceButton,
                eventNumber: eventNumber,
                generation: generation
            ) else {
                return false
            }

            state = .physicalConsumed(sessionID: sessionID, generation: generation)
            return true
        }
    }

    func quiesce() -> MiddleClickPendingRelease? {
        withLock {
            guard accepting else { return nil }
            accepting = false
            currentGeneration &+= 1
            lastSequence = nil

            let pendingRelease: MiddleClickPendingRelease?
            if case .physicalPending(_, let sourceButton, let eventNumber, let generation) = state {
                pendingRelease = MiddleClickPendingRelease(
                    sourceButton: sourceButton,
                    eventNumber: eventNumber,
                    generation: generation
                )
            } else {
                pendingRelease = nil
            }

            state = .idle
            return pendingRelease
        }
    }

    private func matchesPending(
        sourceButton: Int64,
        eventNumber: Int64,
        generation: UInt64
    ) -> UInt64? {
        guard accepting,
              generation == currentGeneration,
              case .physicalPending(
                  let sessionID,
                  let pendingButton,
                  let pendingEventNumber,
                  let pendingGeneration
              ) = state,
              pendingButton == sourceButton,
              pendingEventNumber == eventNumber,
              pendingGeneration == generation else {
            return nil
        }
        return sessionID
    }

    private func withLock<Result>(_ body: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
