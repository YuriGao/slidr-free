import Foundation

public struct FeatureToggles: Codable, Equatable, Sendable {
    public var volumeEdgeGesture: Bool
    public var brightnessEdgeGesture: Bool
    public var middleClick: Bool
    public var fineControl: Bool
    public var swapSides: Bool
    public var bottomQuarterOnly: Bool
    public var smartTypingDetection: Bool
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var edgeWidthPercent: Double
    public var sensitivity: Double
    public var normalStep: Double
    public var fineStep: Double
    public var typingCooldownSeconds: Double
    public var continuousWindowSeconds: Double
    public var physicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double

    public init(
        edgeWidthPercent: Double,
        sensitivity: Double,
        normalStep: Double,
        fineStep: Double,
        typingCooldownSeconds: Double,
        continuousWindowSeconds: Double,
        physicalStepDistance: Double,
        physicalStepIntervalSeconds: Double
    ) {
        self.edgeWidthPercent = edgeWidthPercent
        self.sensitivity = sensitivity
        self.normalStep = normalStep
        self.fineStep = fineStep
        self.typingCooldownSeconds = typingCooldownSeconds
        self.continuousWindowSeconds = continuousWindowSeconds
        self.physicalStepDistance = physicalStepDistance
        self.physicalStepIntervalSeconds = physicalStepIntervalSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case edgeWidthPercent
        case sensitivity
        case normalStep
        case fineStep
        case typingCooldownSeconds
        case continuousWindowSeconds
        case physicalStepDistance
        case physicalStepIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.edgeWidthPercent = try container.decode(Double.self, forKey: .edgeWidthPercent)
        self.sensitivity = try container.decode(Double.self, forKey: .sensitivity)
        self.normalStep = try container.decode(Double.self, forKey: .normalStep)
        self.fineStep = try container.decode(Double.self, forKey: .fineStep)
        self.typingCooldownSeconds = try container.decode(Double.self, forKey: .typingCooldownSeconds)
        self.continuousWindowSeconds = try container.decode(Double.self, forKey: .continuousWindowSeconds)
        self.physicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .physicalStepDistance) ?? AppSettings.default.gesture.physicalStepDistance
        self.physicalStepIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .physicalStepIntervalSeconds) ?? AppSettings.default.gesture.physicalStepIntervalSeconds
    }
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
            smartTypingDetection: true
        ),
        gesture: GestureSettings(
            edgeWidthPercent: 0.10,
            sensitivity: 1.0,
            normalStep: 1.0,
            fineStep: 0.35,
            typingCooldownSeconds: 1.0,
            continuousWindowSeconds: 0.35,
            physicalStepDistance: 0.10,
            physicalStepIntervalSeconds: 0.08
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
        copy.gesture.physicalStepDistance = min(max(copy.gesture.physicalStepDistance, 0.02), 0.50)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
        return copy
    }
}
