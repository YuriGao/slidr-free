import Foundation

public enum SideEdgeAction: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case brightness
    case volume
}

public enum TopEdgeAction: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case browserTabs
}

public struct EdgeAssignments: Codable, Equatable, Sendable {
    public var left: SideEdgeAction
    public var right: SideEdgeAction
    public var top: TopEdgeAction

    public init(left: SideEdgeAction, right: SideEdgeAction, top: TopEdgeAction) {
        self.left = left
        self.right = right
        self.top = top
    }

    public init(legacyFeatures: FeatureToggles) {
        if legacyFeatures.swapSides {
            left = legacyFeatures.volumeEdgeGesture ? .volume : .none
            right = legacyFeatures.brightnessEdgeGesture ? .brightness : .none
        } else {
            left = legacyFeatures.brightnessEdgeGesture ? .brightness : .none
            right = legacyFeatures.volumeEdgeGesture ? .volume : .none
        }
        top = legacyFeatures.browserTabEdgeGesture ? .browserTabs : .none
    }
}

public struct ExperienceSettings: Codable, Equatable, Sendable {
    public static let currentOnboardingVersion = 1
    public var onboardingVersion: Int
    public var hasSeenV04Welcome: Bool

    public init(onboardingVersion: Int, hasSeenV04Welcome: Bool = false) {
        self.onboardingVersion = max(0, onboardingVersion)
        self.hasSeenV04Welcome = hasSeenV04Welcome
    }
}

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
    public static let physicalStepDistanceRange = 0.02...0.50

    public var edgeWidthPercent: Double
    public var leftPhysicalStepDistance: Double
    public var rightPhysicalStepDistance: Double
    public var topPhysicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double
    public var tabSwitchStepIntervalSeconds: Double
    public var horizontalDominanceRatio: Double

    public init(
        edgeWidthPercent: Double,
        leftPhysicalStepDistance: Double,
        rightPhysicalStepDistance: Double,
        topPhysicalStepDistance: Double,
        physicalStepIntervalSeconds: Double,
        tabSwitchStepIntervalSeconds: Double,
        horizontalDominanceRatio: Double
    ) {
        self.edgeWidthPercent = edgeWidthPercent
        self.leftPhysicalStepDistance = leftPhysicalStepDistance
        self.rightPhysicalStepDistance = rightPhysicalStepDistance
        self.topPhysicalStepDistance = topPhysicalStepDistance
        self.physicalStepIntervalSeconds = physicalStepIntervalSeconds
        self.tabSwitchStepIntervalSeconds = tabSwitchStepIntervalSeconds
        self.horizontalDominanceRatio = horizontalDominanceRatio
    }

    /// Source-compatible initializer for callers that still provide the legacy
    /// shared distance. Persisted legacy values are migrated the same way.
    public init(
        edgeWidthPercent: Double,
        physicalStepDistance: Double,
        physicalStepIntervalSeconds: Double,
        tabSwitchStepIntervalSeconds: Double,
        horizontalDominanceRatio: Double
    ) {
        self.init(
            edgeWidthPercent: edgeWidthPercent,
            leftPhysicalStepDistance: physicalStepDistance,
            rightPhysicalStepDistance: physicalStepDistance,
            topPhysicalStepDistance: physicalStepDistance,
            physicalStepIntervalSeconds: physicalStepIntervalSeconds,
            tabSwitchStepIntervalSeconds: tabSwitchStepIntervalSeconds,
            horizontalDominanceRatio: horizontalDominanceRatio
        )
    }

    private enum CodingKeys: String, CodingKey {
        case edgeWidthPercent
        case leftPhysicalStepDistance
        case rightPhysicalStepDistance
        case topPhysicalStepDistance
        case physicalStepDistance
        case physicalStepIntervalSeconds
        case tabSwitchStepIntervalSeconds
        case horizontalDominanceRatio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.edgeWidthPercent = try container.decode(Double.self, forKey: .edgeWidthPercent)
        let legacyPhysicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .physicalStepDistance)
        self.leftPhysicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .leftPhysicalStepDistance)
            ?? legacyPhysicalStepDistance
            ?? AppSettings.default.gesture.leftPhysicalStepDistance
        self.rightPhysicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .rightPhysicalStepDistance)
            ?? legacyPhysicalStepDistance
            ?? AppSettings.default.gesture.rightPhysicalStepDistance
        self.topPhysicalStepDistance = try container.decodeIfPresent(Double.self, forKey: .topPhysicalStepDistance)
            ?? legacyPhysicalStepDistance
            ?? AppSettings.default.gesture.topPhysicalStepDistance
        self.physicalStepIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .physicalStepIntervalSeconds) ?? AppSettings.default.gesture.physicalStepIntervalSeconds
        self.tabSwitchStepIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .tabSwitchStepIntervalSeconds) ?? AppSettings.default.gesture.tabSwitchStepIntervalSeconds
        self.horizontalDominanceRatio = try container.decodeIfPresent(Double.self, forKey: .horizontalDominanceRatio) ?? AppSettings.default.gesture.horizontalDominanceRatio
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(edgeWidthPercent, forKey: .edgeWidthPercent)
        try container.encode(leftPhysicalStepDistance, forKey: .leftPhysicalStepDistance)
        try container.encode(rightPhysicalStepDistance, forKey: .rightPhysicalStepDistance)
        try container.encode(topPhysicalStepDistance, forKey: .topPhysicalStepDistance)
        try container.encode(physicalStepIntervalSeconds, forKey: .physicalStepIntervalSeconds)
        try container.encode(tabSwitchStepIntervalSeconds, forKey: .tabSwitchStepIntervalSeconds)
        try container.encode(horizontalDominanceRatio, forKey: .horizontalDominanceRatio)
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var isAppEnabled: Bool
    public var launchAtLogin: Bool
    public var features: FeatureToggles
    public var gesture: GestureSettings
    public var middleClick: MiddleClickSettings
    public var edgeAssignments: EdgeAssignments
    public var experience: ExperienceSettings

    public var hasConfiguredGesture: Bool {
        middleClick.isEnabled || edgeAssignments.left != .none || edgeAssignments.right != .none || edgeAssignments.top != .none
    }

    private enum CodingKeys: String, CodingKey {
        case isAppEnabled
        case launchAtLogin
        case features
        case gesture
        case middleClick
        case edgeAssignments
        case experience
    }

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
            leftPhysicalStepDistance: 0.05,
            rightPhysicalStepDistance: 0.05,
            topPhysicalStepDistance: 0.05,
            physicalStepIntervalSeconds: 0.08,
            tabSwitchStepIntervalSeconds: 0.20,
            horizontalDominanceRatio: 1.5
        ),
        middleClick: .default,
        edgeAssignments: EdgeAssignments(left: .brightness, right: .volume, top: .browserTabs),
        experience: ExperienceSettings(onboardingVersion: ExperienceSettings.currentOnboardingVersion, hasSeenV04Welcome: true)
    )

    public static let newInstall = AppSettings(
        isAppEnabled: false,
        launchAtLogin: false,
        features: FeatureToggles(
            volumeEdgeGesture: true,
            brightnessEdgeGesture: true,
            browserTabEdgeGesture: true,
            swapSides: false
        ),
        gesture: AppSettings.default.gesture,
        middleClick: .default,
        edgeAssignments: EdgeAssignments(left: .brightness, right: .volume, top: .browserTabs),
        experience: ExperienceSettings(onboardingVersion: 0)
    )

    public init(
        isAppEnabled: Bool,
        launchAtLogin: Bool,
        features: FeatureToggles,
        gesture: GestureSettings,
        middleClick: MiddleClickSettings,
        edgeAssignments: EdgeAssignments? = nil,
        experience: ExperienceSettings = ExperienceSettings(onboardingVersion: ExperienceSettings.currentOnboardingVersion, hasSeenV04Welcome: false)
    ) {
        self.isAppEnabled = isAppEnabled
        self.launchAtLogin = launchAtLogin
        self.features = features
        self.gesture = gesture
        self.middleClick = middleClick
        self.edgeAssignments = edgeAssignments ?? EdgeAssignments(legacyFeatures: features)
        self.experience = experience
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isAppEnabled = try container.decode(Bool.self, forKey: .isAppEnabled)
        self.launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        self.features = try container.decode(FeatureToggles.self, forKey: .features)
        self.gesture = try container.decode(GestureSettings.self, forKey: .gesture)
        self.middleClick = try container.decodeIfPresent(MiddleClickSettings.self, forKey: .middleClick) ?? Self.default.middleClick
        self.edgeAssignments = try container.decodeIfPresent(EdgeAssignments.self, forKey: .edgeAssignments)
            ?? EdgeAssignments(legacyFeatures: features)
        self.experience = try container.decodeIfPresent(ExperienceSettings.self, forKey: .experience)
            ?? ExperienceSettings(onboardingVersion: ExperienceSettings.currentOnboardingVersion)
    }

    public func validated() -> AppSettings {
        var copy = self
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, 0.04), 0.20)
        let distanceRange = GestureSettings.physicalStepDistanceRange
        copy.gesture.leftPhysicalStepDistance = min(max(copy.gesture.leftPhysicalStepDistance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.gesture.rightPhysicalStepDistance = min(max(copy.gesture.rightPhysicalStepDistance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.gesture.topPhysicalStepDistance = min(max(copy.gesture.topPhysicalStepDistance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
        copy.gesture.tabSwitchStepIntervalSeconds = min(max(copy.gesture.tabSwitchStepIntervalSeconds, 0.05), 0.80)
        copy.gesture.horizontalDominanceRatio = min(max(copy.gesture.horizontalDominanceRatio, 1.0), 4.0)
        return copy
    }
}
