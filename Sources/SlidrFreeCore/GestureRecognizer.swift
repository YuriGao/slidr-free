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

    public init(settings: AppSettings = .default) {
        self.settings = settings.validated()
        self.lastKeyDown = nil
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

        case .scroll(let x, let y, let deltaY, let timestamp, let screenSize):
            guard deltaY != 0 else { return nil }
            guard !settings.features.smartTypingDetection || !isInTypingCooldown(timestamp: timestamp) else { return nil }
            guard !settings.features.bottomQuarterOnly || y >= screenSize.height * 0.75 else { return nil }

            let leftEdge = x <= screenSize.width * settings.gesture.edgeWidthPercent
            let rightEdge = x >= screenSize.width * (1 - settings.gesture.edgeWidthPercent)
            guard leftEdge || rightEdge else { return nil }

            let controlsBrightness = settings.features.swapSides ? rightEdge : leftEdge
            let controlsVolume = settings.features.swapSides ? leftEdge : rightEdge
            let direction: GestureDirection = deltaY > 0 ? .increase : .decrease
            let magnitude = min(max(abs(deltaY) / 8.0, 0.25), 3.0)

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
}
