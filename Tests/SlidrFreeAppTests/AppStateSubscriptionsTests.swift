import Combine
import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class AppStateSubscriptionsTests: XCTestCase {
    func testSubscriptionsDeliverPublishedValuesInsteadOfReadingWillSetState() {
        let source = PublishedAppStateSource()
        var receivedSettings: [AppSettings] = []
        var receivedPermissions: [PermissionSnapshot] = []
        let subscriptions = AppStateSubscriptions(
            settingsPublisher: source.$settings.eraseToAnyPublisher(),
            permissionPublisher: source.$permission.eraseToAnyPublisher(),
            onSettings: { receivedSettings.append($0) },
            onPermission: { receivedPermissions.append($0) }
        )

        var disabled = source.settings
        disabled.isAppEnabled = false
        source.settings = disabled
        source.permission = PermissionSnapshot(accessibility: .denied)

        XCTAssertEqual(receivedSettings.last, disabled)
        XCTAssertEqual(receivedPermissions, [PermissionSnapshot(accessibility: .denied)])
        withExtendedLifetime(subscriptions) {}
    }
}

private final class PublishedAppStateSource {
    @Published var settings = AppSettings.default
    @Published var permission = PermissionSnapshot(accessibility: .granted)
}
