import Foundation

public struct MiddleClickSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var tapEnabled: Bool
    public var fingerCount: Int

    public static let supportedFingerCounts = 2...4
    public static let `default` = Self(isEnabled: false, tapEnabled: true, fingerCount: 4)

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case tapEnabled
        case fingerCount
    }

    public init(isEnabled: Bool, tapEnabled: Bool, fingerCount: Int = 4) {
        self.isEnabled = isEnabled
        self.tapEnabled = tapEnabled
        self.fingerCount = Self.validatedFingerCount(fingerCount)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled,
            tapEnabled: try container.decodeIfPresent(Bool.self, forKey: .tapEnabled) ?? Self.default.tapEnabled,
            fingerCount: try container.decodeIfPresent(Int.self, forKey: .fingerCount) ?? Self.default.fingerCount
        )
    }

    public static func validatedFingerCount(_ fingerCount: Int) -> Int {
        supportedFingerCounts.contains(fingerCount) ? fingerCount : Self.default.fingerCount
    }
}
