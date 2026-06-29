import Foundation

public struct FeatureToggles: Codable, Equatable, Sendable {
    public var volumeEdgeGesture: Bool
    public var brightnessEdgeGesture: Bool
    public var browserTabEdgeGesture: Bool
    public var swapSides: Bool

    private enum CodingKeys: String, CodingKey {
        case volumeEdgeGesture
        case brightnessEdgeGesture
        case browserTabEdgeGesture
        case swapSides
    }

    public init(
        volumeEdgeGesture: Bool,
        brightnessEdgeGesture: Bool,
        browserTabEdgeGesture: Bool,
        swapSides: Bool
    ) {
        self.volumeEdgeGesture = volumeEdgeGesture
        self.brightnessEdgeGesture = brightnessEdgeGesture
        self.browserTabEdgeGesture = browserTabEdgeGesture
        self.swapSides = swapSides
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.volumeEdgeGesture = try container.decode(Bool.self, forKey: .volumeEdgeGesture)
        self.brightnessEdgeGesture = try container.decode(Bool.self, forKey: .brightnessEdgeGesture)
        self.browserTabEdgeGesture = try container.decodeIfPresent(Bool.self, forKey: .browserTabEdgeGesture) ?? AppSettings.default.features.browserTabEdgeGesture
        self.swapSides = try container.decode(Bool.self, forKey: .swapSides)
    }
}

public struct GestureSettings: Codable, Equatable, Sendable {
    public var edgeWidthPercent: Double
    public var physicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double
    public var tabSwitchStepIntervalSeconds: Double
    public var horizontalDominanceRatio: Double

    public init(
        edgeWidthPercent: Double,
        physicalStepDistance: Double,
        physicalStepIntervalSeconds: Double,
        tabSwitchStepIntervalSeconds: Double,
        horizontalDominanceRatio: Double
    ) {
        self.edgeWidthPercent = edgeWidthPercent
        self.physicalStepDistance = physicalStepDistance
        self.physicalStepIntervalSeconds = physicalStepIntervalSeconds
        self.tabSwitchStepIntervalSeconds = tabSwitchStepIntervalSeconds
        self.horizontalDominanceRatio = horizontalDominanceRatio
    }

    private enum CodingKeys: String, CodingKey {
        case edgeWidthPercent
        case physicalStepDistance
        case physicalStepIntervalSeconds
        case tabSwitchStepIntervalSeconds
        case horizontalDominanceRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.edgeWidthPercent = try container.decode(Double.self, forKey: .edgeWidthPercent)
        self.physicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .physicalStepDistance) ?? AppSettings.default.gesture.physicalStepDistance
        self.physicalStepIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .physicalStepIntervalSeconds) ?? AppSettings.default.gesture.physicalStepIntervalSeconds
        self.tabSwitchStepIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .tabSwitchStepIntervalSeconds) ?? AppSettings.default.gesture.tabSwitchStepIntervalSeconds
        self.horizontalDominanceRatio = try container.decodeIfPresent(Double.self, forKey: .horizontalDominanceRatio) ?? AppSettings.default.gesture.horizontalDominanceRatio
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
            browserTabEdgeGesture: true,
            swapSides: false
        ),
        gesture: GestureSettings(
            edgeWidthPercent: 0.10,
            physicalStepDistance: 0.05,
            physicalStepIntervalSeconds: 0.08,
            tabSwitchStepIntervalSeconds: 0.20,
            horizontalDominanceRatio: 1.5
        )
    )

    public func validated() -> AppSettings {
        var copy = self
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, 0.04), 0.20)
        copy.gesture.physicalStepDistance = min(max(copy.gesture.physicalStepDistance, 0.02), 0.50)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
        copy.gesture.tabSwitchStepIntervalSeconds = min(max(copy.gesture.tabSwitchStepIntervalSeconds, 0.05), 0.80)
        copy.gesture.horizontalDominanceRatio = min(max(copy.gesture.horizontalDominanceRatio, 1.0), 4.0)
        return copy
    }
}
