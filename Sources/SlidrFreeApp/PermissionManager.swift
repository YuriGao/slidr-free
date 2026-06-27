import AppKit
import ApplicationServices
import CoreGraphics
import ServiceManagement
import SlidrFreeCore

final class PermissionManager: ObservableObject {
    @Published private(set) var snapshot: PermissionSnapshot

    init() {
        snapshot = Self.currentSnapshot()
    }

    static func currentSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(
            accessibility: AXIsProcessTrusted() ? .granted : .denied,
            inputMonitoring: CGPreflightListenEventAccess() ? .granted : .denied
        )
    }

    @discardableResult
    func currentSnapshot() -> PermissionSnapshot {
        let updated = Self.currentSnapshot()
        snapshot = updated
        return updated
    }

    func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        currentSnapshot()
    }

    func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
