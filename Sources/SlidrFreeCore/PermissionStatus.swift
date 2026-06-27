public enum PermissionState: String, Codable, Equatable {
    case granted
    case denied
    case unknown
}

public struct PermissionSnapshot: Codable, Equatable {
    public var accessibility: PermissionState
    public var inputMonitoring: PermissionState

    public var canListen: Bool {
        accessibility == .granted && inputMonitoring == .granted
    }

    public init(accessibility: PermissionState, inputMonitoring: PermissionState) {
        self.accessibility = accessibility
        self.inputMonitoring = inputMonitoring
    }
}
