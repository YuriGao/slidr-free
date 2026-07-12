import Foundation
import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class SettingsStoreMigrationTests: XCTestCase {
    func testV02PayloadPreservesEveryFieldAndRoundTripsWithMiddleClickDefaults() throws {
        let defaults = isolatedDefaults()
        let payload = #"{"isAppEnabled":false,"launchAtLogin":true,"features":{"volumeEdgeGesture":false,"brightnessEdgeGesture":true,"browserTabEdgeGesture":false,"swapSides":true},"gesture":{"edgeWidthPercent":0.17,"physicalStepDistance":0.13,"physicalStepIntervalSeconds":0.22,"tabSwitchStepIntervalSeconds":0.31,"horizontalDominanceRatio":2.4}}"#.data(using: .utf8)!
        defaults.set(payload, forKey: SettingsStore.defaultsKey)

        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.settings, AppSettings(
            isAppEnabled: false,
            launchAtLogin: true,
            features: FeatureToggles(volumeEdgeGesture: false, brightnessEdgeGesture: true, browserTabEdgeGesture: false, swapSides: true),
            gesture: GestureSettings(edgeWidthPercent: 0.17, physicalStepDistance: 0.13, physicalStepIntervalSeconds: 0.22, tabSwitchStepIntervalSeconds: 0.31, horizontalDominanceRatio: 2.4),
            middleClick: .default
        ))

        store.save(store.settings)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, store.settings)
    }

    func testCorruptPayloadFallsBackAndRecordsBoundedNonSensitiveDiagnostic() {
        let defaults = isolatedDefaults()
        defaults.set(Data("not-json-secret-material".utf8), forKey: SettingsStore.defaultsKey)
        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.settings, .default.validated())
        XCTAssertNotNil(store.lastLoadDiagnostic)
        XCTAssertLessThanOrEqual(store.lastLoadDiagnostic?.count ?? 999, 160)
        XCTAssertFalse(store.lastLoadDiagnostic?.contains("secret-material") ?? true)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
