import Foundation

public enum SystemAction: Equatable, Sendable {
    case adjustBrightness(delta: Double)
    case adjustVolume(delta: Double)
    case middleClick(x: Double, y: Double)
}

public struct ActionDispatcher: Sendable {
    public var settings: AppSettings

    public init(settings: AppSettings = .default) {
        self.settings = settings.validated()
    }

    public func actions(for gesture: RecognizedGesture) -> [SystemAction] {
        switch gesture {
        case .brightness(let direction, let magnitude):
            return [.adjustBrightness(delta: signedDelta(direction: direction, magnitude: magnitude))]
        case .volume(let direction, let magnitude):
            return [.adjustVolume(delta: signedDelta(direction: direction, magnitude: magnitude))]
        case .middleClick(let x, let y):
            guard settings.features.middleClick else { return [] }
            return [.middleClick(x: x, y: y)]
        }
    }

    private func signedDelta(direction: GestureDirection, magnitude: Double) -> Double {
        let sign = direction == .increase ? 1.0 : -1.0
        return sign * magnitude
    }
}
