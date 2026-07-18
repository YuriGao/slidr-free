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

public struct ApplicationBinding: Codable, Equatable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String
    public var applicationPath: String

    public init(bundleIdentifier: String, displayName: String, applicationPath: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.applicationPath = applicationPath
    }

    fileprivate func validated() -> ApplicationBinding? {
        let identifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = applicationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty,
              !name.isEmpty,
              !path.isEmpty,
              path.hasPrefix("/"),
              URL(fileURLWithPath: path).pathExtension.lowercased() == "app" else { return nil }
        return ApplicationBinding(bundleIdentifier: identifier, displayName: name, applicationPath: path)
    }
}

public struct CornerAppBindings: Codable, Equatable, Sendable {
    public var topLeft: ApplicationBinding?
    public var topRight: ApplicationBinding?
    public var bottomLeft: ApplicationBinding?
    public var bottomRight: ApplicationBinding?

    public static let empty = CornerAppBindings()

    public init(
        topLeft: ApplicationBinding? = nil,
        topRight: ApplicationBinding? = nil,
        bottomLeft: ApplicationBinding? = nil,
        bottomRight: ApplicationBinding? = nil
    ) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }

    public subscript(corner: TrackpadCorner) -> ApplicationBinding? {
        get {
            switch corner {
            case .topLeft: return topLeft
            case .topRight: return topRight
            case .bottomLeft: return bottomLeft
            case .bottomRight: return bottomRight
            }
        }
        set {
            switch corner {
            case .topLeft: topLeft = newValue
            case .topRight: topRight = newValue
            case .bottomLeft: bottomLeft = newValue
            case .bottomRight: bottomRight = newValue
            }
        }
    }

    public var hasAnyBinding: Bool {
        TrackpadCorner.allCases.contains { self[$0] != nil }
    }

    fileprivate func validated() -> CornerAppBindings {
        CornerAppBindings(
            topLeft: topLeft?.validated(),
            topRight: topRight?.validated(),
            bottomLeft: bottomLeft?.validated(),
            bottomRight: bottomRight?.validated()
        )
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
    public static let edgeWidthPercentRange = 0.04...0.20
    public static let cornerTriggerPercentRange = 0.04...0.20
    public static let defaultCornerTriggerPercent = 0.10
    public static let cornerMovementTolerancePercentRange = 0.01...0.10
    public static let defaultCornerMovementTolerancePercent = 0.03
    public static let cornerDoubleTapIntervalRange = 0.30...1.20
    public static let defaultCornerDoubleTapIntervalSeconds = 0.75
    public static let physicalStepDistanceRange = 0.02...0.50

    public var edgeWidthPercent: Double
    public var cornerTriggerPercent: Double
    public var cornerMovementTolerancePercent: Double
    public var cornerDoubleTapIntervalSeconds: Double
    public var leftPhysicalStepDistance: Double
    public var rightPhysicalStepDistance: Double
    public var topPhysicalStepDistance: Double
    public var physicalStepIntervalSeconds: Double
    public var tabSwitchStepIntervalSeconds: Double
    public var horizontalDominanceRatio: Double

    public init(
        edgeWidthPercent: Double,
        cornerTriggerPercent: Double = GestureSettings.defaultCornerTriggerPercent,
        cornerMovementTolerancePercent: Double = GestureSettings.defaultCornerMovementTolerancePercent,
        cornerDoubleTapIntervalSeconds: Double = GestureSettings.defaultCornerDoubleTapIntervalSeconds,
        leftPhysicalStepDistance: Double,
        rightPhysicalStepDistance: Double,
        topPhysicalStepDistance: Double,
        physicalStepIntervalSeconds: Double,
        tabSwitchStepIntervalSeconds: Double,
        horizontalDominanceRatio: Double
    ) {
        self.edgeWidthPercent = edgeWidthPercent
        self.cornerTriggerPercent = cornerTriggerPercent
        self.cornerMovementTolerancePercent = cornerMovementTolerancePercent
        self.cornerDoubleTapIntervalSeconds = cornerDoubleTapIntervalSeconds
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
        cornerTriggerPercent: Double = GestureSettings.defaultCornerTriggerPercent,
        cornerMovementTolerancePercent: Double = GestureSettings.defaultCornerMovementTolerancePercent,
        cornerDoubleTapIntervalSeconds: Double = GestureSettings.defaultCornerDoubleTapIntervalSeconds,
        physicalStepDistance: Double,
        physicalStepIntervalSeconds: Double,
        tabSwitchStepIntervalSeconds: Double,
        horizontalDominanceRatio: Double
    ) {
        self.init(
            edgeWidthPercent: edgeWidthPercent,
            cornerTriggerPercent: cornerTriggerPercent,
            cornerMovementTolerancePercent: cornerMovementTolerancePercent,
            cornerDoubleTapIntervalSeconds: cornerDoubleTapIntervalSeconds,
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
        case cornerTriggerPercent
        case cornerMovementTolerancePercent
        case cornerDoubleTapIntervalSeconds
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
        self.cornerTriggerPercent = try container.decodeIfPresent(Double.self, forKey: .cornerTriggerPercent)
            ?? Self.defaultCornerTriggerPercent
        self.cornerMovementTolerancePercent = try container.decodeIfPresent(Double.self, forKey: .cornerMovementTolerancePercent)
            ?? Self.defaultCornerMovementTolerancePercent
        self.cornerDoubleTapIntervalSeconds = try container.decodeIfPresent(Double.self, forKey: .cornerDoubleTapIntervalSeconds)
            ?? Self.defaultCornerDoubleTapIntervalSeconds
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
        try container.encode(cornerTriggerPercent, forKey: .cornerTriggerPercent)
        try container.encode(cornerMovementTolerancePercent, forKey: .cornerMovementTolerancePercent)
        try container.encode(cornerDoubleTapIntervalSeconds, forKey: .cornerDoubleTapIntervalSeconds)
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
    public var cornerAppBindings: CornerAppBindings
    public var experience: ExperienceSettings

    public var hasConfiguredGesture: Bool {
        middleClick.isEnabled
            || edgeAssignments.left != .none
            || edgeAssignments.right != .none
            || edgeAssignments.top != .none
            || cornerAppBindings.hasAnyBinding
    }

    private enum CodingKeys: String, CodingKey {
        case isAppEnabled
        case launchAtLogin
        case features
        case gesture
        case middleClick
        case edgeAssignments
        case cornerAppBindings
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
            cornerTriggerPercent: GestureSettings.defaultCornerTriggerPercent,
            cornerMovementTolerancePercent: GestureSettings.defaultCornerMovementTolerancePercent,
            cornerDoubleTapIntervalSeconds: GestureSettings.defaultCornerDoubleTapIntervalSeconds,
            leftPhysicalStepDistance: 0.05,
            rightPhysicalStepDistance: 0.05,
            topPhysicalStepDistance: 0.05,
            physicalStepIntervalSeconds: 0.08,
            tabSwitchStepIntervalSeconds: 0.20,
            horizontalDominanceRatio: 1.5
        ),
        middleClick: .default,
        edgeAssignments: EdgeAssignments(left: .brightness, right: .volume, top: .browserTabs),
        cornerAppBindings: .empty,
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
        cornerAppBindings: .empty,
        experience: ExperienceSettings(onboardingVersion: 0)
    )

    public init(
        isAppEnabled: Bool,
        launchAtLogin: Bool,
        features: FeatureToggles,
        gesture: GestureSettings,
        middleClick: MiddleClickSettings,
        edgeAssignments: EdgeAssignments? = nil,
        cornerAppBindings: CornerAppBindings = .empty,
        experience: ExperienceSettings = ExperienceSettings(onboardingVersion: ExperienceSettings.currentOnboardingVersion, hasSeenV04Welcome: false)
    ) {
        self.isAppEnabled = isAppEnabled
        self.launchAtLogin = launchAtLogin
        self.features = features
        self.gesture = gesture
        self.middleClick = middleClick
        self.edgeAssignments = edgeAssignments ?? EdgeAssignments(legacyFeatures: features)
        self.cornerAppBindings = cornerAppBindings
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
        self.cornerAppBindings = try container.decodeIfPresent(CornerAppBindings.self, forKey: .cornerAppBindings) ?? .empty
        self.experience = try container.decodeIfPresent(ExperienceSettings.self, forKey: .experience)
            ?? ExperienceSettings(onboardingVersion: ExperienceSettings.currentOnboardingVersion)
    }

    public func validated() -> AppSettings {
        var copy = self
        let edgeWidthRange = GestureSettings.edgeWidthPercentRange
        copy.gesture.edgeWidthPercent = min(max(copy.gesture.edgeWidthPercent, edgeWidthRange.lowerBound), edgeWidthRange.upperBound)
        let cornerTriggerRange = GestureSettings.cornerTriggerPercentRange
        copy.gesture.cornerTriggerPercent = min(max(copy.gesture.cornerTriggerPercent, cornerTriggerRange.lowerBound), cornerTriggerRange.upperBound)
        let cornerMovementToleranceRange = GestureSettings.cornerMovementTolerancePercentRange
        copy.gesture.cornerMovementTolerancePercent = min(
            max(copy.gesture.cornerMovementTolerancePercent, cornerMovementToleranceRange.lowerBound),
            cornerMovementToleranceRange.upperBound
        )
        let cornerDoubleTapIntervalRange = GestureSettings.cornerDoubleTapIntervalRange
        copy.gesture.cornerDoubleTapIntervalSeconds = min(
            max(copy.gesture.cornerDoubleTapIntervalSeconds, cornerDoubleTapIntervalRange.lowerBound),
            cornerDoubleTapIntervalRange.upperBound
        )
        let distanceRange = GestureSettings.physicalStepDistanceRange
        copy.gesture.leftPhysicalStepDistance = min(max(copy.gesture.leftPhysicalStepDistance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.gesture.rightPhysicalStepDistance = min(max(copy.gesture.rightPhysicalStepDistance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.gesture.topPhysicalStepDistance = min(max(copy.gesture.topPhysicalStepDistance, distanceRange.lowerBound), distanceRange.upperBound)
        copy.gesture.physicalStepIntervalSeconds = min(max(copy.gesture.physicalStepIntervalSeconds, 0.0), 0.50)
        copy.gesture.tabSwitchStepIntervalSeconds = min(max(copy.gesture.tabSwitchStepIntervalSeconds, 0.05), 0.80)
        copy.gesture.horizontalDominanceRatio = min(max(copy.gesture.horizontalDominanceRatio, 1.0), 4.0)
        copy.cornerAppBindings = copy.cornerAppBindings.validated()
        return copy
    }
}
