import Foundation

public struct MiddleClickSettings: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var tapEnabled: Bool

    public static let `default` = Self(isEnabled: false, tapEnabled: true)

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case tapEnabled
    }

    public init(isEnabled: Bool, tapEnabled: Bool) {
        self.isEnabled = isEnabled
        self.tapEnabled = tapEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? Self.default.isEnabled
        self.tapEnabled = try container.decodeIfPresent(Bool.self, forKey: .tapEnabled) ?? Self.default.tapEnabled
    }
}
