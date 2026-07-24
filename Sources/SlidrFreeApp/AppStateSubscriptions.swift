import Combine
import SlidrFreeCore

final class AppStateSubscriptions {
    private var cancellables = Set<AnyCancellable>()

    init(
        settingsPublisher: AnyPublisher<AppSettings, Never>,
        permissionPublisher: AnyPublisher<PermissionSnapshot, Never>,
        onSettings: @escaping (AppSettings) -> Void,
        onPermission: @escaping (PermissionSnapshot) -> Void
    ) {
        settingsPublisher
            .sink(receiveValue: onSettings)
            .store(in: &cancellables)

        permissionPublisher
            .dropFirst()
            .sink(receiveValue: onPermission)
            .store(in: &cancellables)
    }
}
