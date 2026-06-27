import Foundation

public struct FeatureToggles: Codable, Equatable, Sendable {
    public var volumeEdgeGesture: Bool
    public var brightnessEdgeGesture: Bool
    public var middleClick: Bool
    public var fineControl: Bool
    public var swapSides: Bool
    public var bottomQuarterOnly: Bool
    public var smartTypingDetection: Bool
    public var cursorFreeze: Bool
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var edgeWidthPercent: Double
    public var sensitivity: Double
    public var normalStep: Double
    public var fineStep: Double
    public var typingCooldownSeconds: Double
    public var continuousWindowSeconds: Double
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var isAppEnabled: Bool
    public var launchAtLogin: Bool
    public var features: FeatureToggles
    public var gesture: GestureSettings

    public static let `default` = AppSettings(
        isAppEnabled: true,
        launchAtLogin: false,
        features: FeatureToggles(
            volumeEdgeGesture: true,
            brightnessEdgeGesture: true,
            middleClick: true,
            fineControl: true,
            swapSides: false,
            bottomQuarterOnly: false,
            smartTypingDetection: true,
            cursorFreeze: true
        ),
        gesture: GestureSettings(
            edgeWidthPercent: 0.10,
            sensitivity: 1.0,
            normalStep: 1.0,
            fineStep: 0.35,
            typingCooldownSeconds: 1.0,
            continuousWindowSeconds: 0.35
        )
    )

    public func validated() -> AppSettings {
        var copy = self
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, 0.04), 0.20)
        copy.gesture.sensitivity = min(max(copy.gesture.sensitivity, 0.10), 4.0)
        copy.gesture.normalStep = min(max(copy.gesture.normalStep, 0.10), 10.0)
        copy.gesture.fineStep = min(max(copy.gesture.fineStep, 0.05), copy.gesture.normalStep)
        copy.gesture.typingCooldownSeconds = min(max(copy.gesture.typingCooldownSeconds, 0.0), 2.0)
        copy.gesture.continuousWindowSeconds = min(max(copy.gesture.continuousWindowSeconds, 0.05), 1.0)
        return copy
    }
}
