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

    public init(settings: AppSettings = .default) {
        self.settings = settings.validated()
        self.lastKeyDown = nil
        self.previousPrimaryPhysicalTouch = nil
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
                return nil
            }
            guard let current = touches.first else {
                previousPrimaryPhysicalTouch = nil
                return nil
            }
            guard !settings.features.bottomQuarterOnly || current.y >= 0.75 else {
                previousPrimaryPhysicalTouch = current
                return nil
            }

            let edgeHit = physicalEdgeHit(for: current.x)
            guard let edgeHit else {
                previousPrimaryPhysicalTouch = current
                return nil
            }

            guard let previous = previousPrimaryPhysicalTouch, previous.id == current.id else {
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
            let direction: GestureDirection = deltaY > 0 ? .increase : .decrease
            let magnitude = min(max(abs(deltaY) / 0.12, 0.25), 3.0)

            if controlsBrightness && settings.features.brightnessEdgeGesture {
                return .brightness(direction: direction, magnitude: magnitude)
            }

            if controlsVolume && settings.features.volumeEdgeGesture {
                return .volume(direction: direction, magnitude: magnitude)
            }

            return nil
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
}
