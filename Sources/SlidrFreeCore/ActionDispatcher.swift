import Foundation

public enum SystemAction: Equatable, Sendable {
    case adjustBrightness(delta: Double)
    case adjustVolume(delta: Double)
    case switchBrowserTab(direction: BrowserTabDirection)
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
        case .browserTab(let direction):
            return [.switchBrowserTab(direction: direction)]
        }
    }

    private func signedDelta(direction: GestureDirection, magnitude: Double) -> Double {
        let sign = direction == .increase ? 1.0 : -1.0
        return sign * magnitude
    }
}
