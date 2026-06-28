public enum PermissionState: String, Codable, Equatable {
    case granted
    case denied
    case unknown
}

public struct PermissionSnapshot: Codable, Equatable {
    public var accessibility: PermissionState

    public var canListen: Bool {
        accessibility == .granted
    }

    public init(accessibility: PermissionState) {
        self.accessibility = accessibility
    }
}
