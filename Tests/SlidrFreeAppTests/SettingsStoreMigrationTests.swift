import Foundation
import SlidrFreeCore
import XCTest
@testable import SlidrFreeApp

final class SettingsStoreMigrationTests: XCTestCase {
    func testNewInstallStartsDisabledAndRequiresOnboarding() {
        let store = SettingsStore(defaults: isolatedDefaults())
        XCTAssertTrue(store.isNewInstall)
        XCTAssertFalse(store.settings.isAppEnabled)
        XCTAssertEqual(store.settings.experience.onboardingVersion, 0)
    }

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
        XCTAssertFalse(store.isNewInstall)
        XCTAssertEqual(store.settings.experience.onboardingVersion, ExperienceSettings.currentOnboardingVersion)
        XCTAssertFalse(store.settings.experience.hasSeenV04Welcome)

        store.save(store.settings)
        XCTAssertEqual(SettingsStore(defaults: defaults).settings, store.settings)

        let savedData = try XCTUnwrap(defaults.data(forKey: SettingsStore.defaultsKey))
        let savedRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: savedData) as? [String: Any])
        let savedGesture = try XCTUnwrap(savedRoot["gesture"] as? [String: Any])
        XCTAssertEqual(store.settings.gesture.cornerTriggerPercent, GestureSettings.defaultCornerTriggerPercent)
        XCTAssertEqual(store.settings.gesture.cornerMovementTolerancePercent, GestureSettings.defaultCornerMovementTolerancePercent)
        XCTAssertEqual(store.settings.gesture.cornerDoubleTapIntervalSeconds, GestureSettings.defaultCornerDoubleTapIntervalSeconds)
        XCTAssertNotEqual(store.settings.gesture.cornerTriggerPercent, store.settings.gesture.edgeWidthPercent)
        XCTAssertEqual(savedGesture["cornerTriggerPercent"] as? Double, GestureSettings.defaultCornerTriggerPercent)
        XCTAssertEqual(savedGesture["cornerMovementTolerancePercent"] as? Double, GestureSettings.defaultCornerMovementTolerancePercent)
        XCTAssertEqual(savedGesture["cornerDoubleTapIntervalSeconds"] as? Double, GestureSettings.defaultCornerDoubleTapIntervalSeconds)
        XCTAssertEqual(savedGesture["leftPhysicalStepDistance"] as? Double, 0.13)
        XCTAssertEqual(savedGesture["rightPhysicalStepDistance"] as? Double, 0.13)
        XCTAssertEqual(savedGesture["topPhysicalStepDistance"] as? Double, 0.13)
        XCTAssertNil(savedGesture["physicalStepDistance"])
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

    func testCornerBindingsPersistAndReload() {
        let defaults = isolatedDefaults()
        let store = SettingsStore(defaults: defaults)
        let binding = ApplicationBinding(
            bundleIdentifier: "com.example.app",
            displayName: "Example",
            applicationPath: "/Applications/Example.app"
        )
        var settings = store.settings
        settings.cornerAppBindings.bottomLeft = binding

        store.save(settings)
        let reloaded = SettingsStore(defaults: defaults)

        XCTAssertEqual(reloaded.settings.cornerAppBindings.bottomLeft, binding)
        XCTAssertNil(reloaded.settings.cornerAppBindings.topLeft)
        XCTAssertNil(reloaded.settings.cornerAppBindings.topRight)
        XCTAssertNil(reloaded.settings.cornerAppBindings.bottomRight)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "SettingsStoreMigrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }
}
