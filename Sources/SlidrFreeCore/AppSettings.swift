import Foundation

public struct FeatureToggles: Codable, Equatable, Sendable {
    public var volumeEdgeGesture: Bool
    public var brightnessEdgeGesture: Bool
    public var middleClick: Bool
    public var swapSides: Bool
    public var smartTypingDetection: Bool
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var edgeWidthPercent: Double
    public var typingCooldownSeconds: Double
    public var physicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double

    public init(
        edgeWidthPercent: Double,
        typingCooldownSeconds: Double,
        physicalStepDistance: Double,
        physicalStepIntervalSeconds: Double
    ) {
        self.edgeWidthPercent = edgeWidthPercent
        self.typingCooldownSeconds = typingCooldownSeconds
        self.physicalStepDistance = physicalStepDistance
        self.physicalStepIntervalSeconds = physicalStepIntervalSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case edgeWidthPercent
        case typingCooldownSeconds
        case physicalStepDistance
        case physicalStepIntervalSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.edgeWidthPercent = try container.decode(Double.self, forKey: .edgeWidthPercent)
        self.typingCooldownSeconds = try container.decode(Double.self, forKey: .typingCooldownSeconds)
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
            swapSides: false,
            smartTypingDetection: true
        ),
        gesture: GestureSettings(
            edgeWidthPercent: 0.10,
            typingCooldownSeconds: 1.0,
            physicalStepDistance: 0.10,
            physicalStepIntervalSeconds: 0.08
        )
    )

    public func validated() -> AppSettings {
        var copy = self
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, 0.04), 0.20)
        copy.gesture.typingCooldownSeconds = min(max(copy.gesture.typingCooldownSeconds, 0.0), 2.0)
        copy.gesture.physicalStepDistance = min(max(copy.gesture.physicalStepDistance, 0.02), 0.50)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
        return copy
    }
}
