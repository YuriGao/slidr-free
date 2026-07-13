import Foundation

public struct MiddleClickSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var tapEnabled: Bool
    public var hapticFeedbackEnabled: Bool
    public var fingerCount: Int {
        didSet {
            fingerCount = Self.validatedFingerCount(fingerCount)
        }
    }

    public static let supportedFingerCounts = 2...4
    public static let defaultFingerCount = 4
    public static let `default` = Self(
        isEnabled: false,
        tapEnabled: true,
        fingerCount: defaultFingerCount,
        hapticFeedbackEnabled: true
    )

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case tapEnabled
        case fingerCount
        case hapticFeedbackEnabled
    }

    public init(
        isEnabled: Bool,
        tapEnabled: Bool,
        fingerCount: Int = 4,
        hapticFeedbackEnabled: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.tapEnabled = tapEnabled
        self.fingerCount = Self.validatedFingerCount(fingerCount)
        self.hapticFeedbackEnabled = hapticFeedbackEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled,
            tapEnabled: try container.decodeIfPresent(Bool.self, forKey: .tapEnabled) ?? Self.default.tapEnabled,
            fingerCount: try container.decodeIfPresent(Int.self, forKey: .fingerCount) ?? Self.default.fingerCount,
            hapticFeedbackEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .hapticFeedbackEnabled
            ) ?? Self.default.hapticFeedbackEnabled
        )
    }

    public static func validatedFingerCount(_ fingerCount: Int) -> Int {
        supportedFingerCounts.contains(fingerCount) ? fingerCount : defaultFingerCount
    }
}
