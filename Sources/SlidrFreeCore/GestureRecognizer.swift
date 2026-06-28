import Foundation

public enum RecognizedGesture: Equatable, Sendable {
    case brightness(direction: GestureDirection, magnitude: Double)
    case volume(direction: GestureDirection, magnitude: Double)
    case middleClick(x: Double, y: Double)
}

public enum GestureDirection: Equatable, Sendable {
    case increase
    case decrease
}

public struct GestureRecognizer: Sendable {
    public var settings: AppSettings
    private var lastKeyDown: Double?
    private var previousPrimaryPhysicalTouch: PhysicalTouch?
    private var activePhysicalStep: PhysicalStepState?

    public init(settings: AppSettings = .default) {
        self.settings = settings.validated()
        self.lastKeyDown = nil
        self.previousPrimaryPhysicalTouch = nil
        self.activePhysicalStep = nil
    }

    public mutating func process(_ event: NormalizedInputEvent) -> RecognizedGesture? {
        guard settings.isAppEnabled else { return nil }

        switch event {
        case .keyDown(let timestamp):
            lastKeyDown = timestamp
            return nil

        case .middleClick(let x, let y, _):
            guard settings.features.middleClick else { return nil }
            return .middleClick(x: x, y: y)

        case .scroll:
            return nil

        case .physicalTouchFrame(let touches, let timestamp):
            guard !settings.features.smartTypingDetection || !isInTypingCooldown(timestamp: timestamp) else {
                updatePreviousPrimaryPhysicalTouch(from: touches)
                resetPhysicalStepState()
                return nil
            }
            guard let current = touches.first else {
                resetPhysicalContinuity()
                return nil
            }
            guard !settings.features.bottomQuarterOnly || current.y >= 0.75 else {
                resetPhysicalContinuity()
                return nil
            }

            let edgeHit = physicalEdgeHit(for: current.x)
            guard let edgeHit else {
                resetPhysicalContinuity()
                return nil
            }

            guard let previous = previousPrimaryPhysicalTouch, previous.id == current.id else {
                resetPhysicalStepState()
                previousPrimaryPhysicalTouch = current
                return nil
            }

            guard physicalEdgeHit(for: previous.x) == edgeHit else {
                resetPhysicalStepState()
                previousPrimaryPhysicalTouch = current
                return nil
            }

            let deltaY = current.y - previous.y
            guard deltaY != 0 else {
                previousPrimaryPhysicalTouch = current
                return nil
            }

            previousPrimaryPhysicalTouch = current

            let leftEdge = edgeHit == .left
            let rightEdge = edgeHit == .right
            let controlsBrightness = settings.features.swapSides ? rightEdge : leftEdge
            let controlsVolume = settings.features.swapSides ? leftEdge : rightEdge

            let recognizedKind: PhysicalStepKind?
            if controlsBrightness && settings.features.brightnessEdgeGesture {
                recognizedKind = .brightness
            } else if controlsVolume && settings.features.volumeEdgeGesture {
                recognizedKind = .volume
            } else {
                resetPhysicalStepState()
                return nil
            }

            guard let step = physicalStep(deltaY: deltaY, touchID: current.id, edge: edgeHit, timestamp: timestamp) else {
                return nil
            }

            switch recognizedKind {
            case .brightness:
                return .brightness(direction: step, magnitude: 1.0)
            case .volume:
                return .volume(direction: step, magnitude: 1.0)
            case .none:
                return nil
            }
        }
    }

    private func isInTypingCooldown(timestamp: Double) -> Bool {
        guard let lastKeyDown else { return false }
        return timestamp - lastKeyDown <= settings.gesture.typingCooldownSeconds
    }

    private func physicalEdgeHit(for normalizedX: Double) -> PhysicalEdgeHit? {
        if normalizedX <= settings.gesture.edgeWidthPercent {
            return .left
        }
        if normalizedX >= 1 - settings.gesture.edgeWidthPercent {
            return .right
        }
        return nil
    }

    private mutating func updatePreviousPrimaryPhysicalTouch(from touches: [PhysicalTouch]) {
        previousPrimaryPhysicalTouch = touches.first
    }

    private mutating func resetPhysicalStepState() {
        activePhysicalStep = nil
    }

    private mutating func resetPhysicalContinuity() {
        previousPrimaryPhysicalTouch = nil
        resetPhysicalStepState()
    }

    private mutating func physicalStep(deltaY: Double, touchID: Int, edge: PhysicalEdgeHit, timestamp: Double) -> GestureDirection? {
        let stepDistance = settings.gesture.physicalStepDistance
        if activePhysicalStep?.touchID != touchID || activePhysicalStep?.edge != edge {
            activePhysicalStep = PhysicalStepState(touchID: touchID, edge: edge, accumulatedY: 0, lastEmitTimestamp: nil)
        }

        activePhysicalStep?.accumulatedY += deltaY
        guard let state = activePhysicalStep else { return nil }

        let direction: GestureDirection
        if state.accumulatedY >= stepDistance {
            direction = .increase
        } else if state.accumulatedY <= -stepDistance {
            direction = .decrease
        } else {
            return nil
        }

        if let lastEmitTimestamp = state.lastEmitTimestamp,
           timestamp - lastEmitTimestamp < settings.gesture.physicalStepIntervalSeconds {
            return nil
        }

        let consumed = direction == .increase ? stepDistance : -stepDistance
        activePhysicalStep?.accumulatedY -= consumed
        activePhysicalStep?.lastEmitTimestamp = timestamp
        return direction
    }
}

private struct PhysicalStepState: Sendable {
    var touchID: Int
    var edge: PhysicalEdgeHit
    var accumulatedY: Double
    var lastEmitTimestamp: Double?
}

private enum PhysicalStepKind: Sendable {
    case brightness
    case volume
}
