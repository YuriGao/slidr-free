import AppKit
import CoreGraphics
import SlidrFreeCore

// MARK: - Protocol

public protocol SystemControlling: AnyObject {
    func adjustVolume(delta: Double) -> SystemActionResult
    func adjustBrightness(delta: Double) -> SystemActionResult
    func switchBrowserTab(direction: BrowserTabDirection) -> SystemActionResult
    func middleClick() -> SystemActionResult
}

public enum SystemActionResult: Equatable {
    case success
    case failed(String)
    case unsupported(String)
}

// MARK: - Concrete Implementation

final class SystemControl: SystemControlling {
    private let middleClickEmitter: any MiddleClickEmitting

    init(middleClickEmitter: any MiddleClickEmitting = MiddleClickEmitter()) {
        self.middleClickEmitter = middleClickEmitter
    }

    func adjustVolume(delta: Double) -> SystemActionResult {
        let isUp = delta > 0
        guard postMediaKey(isUp ? .volumeUp : .volumeDown) else {
            let message = "Failed to create media key events"
            logWarning(message)
            return .failed(message)
        }
        return .success
    }

    func adjustBrightness(delta: Double) -> SystemActionResult {
        let isUp = delta > 0
        guard postMediaKey(isUp ? .brightnessUp : .brightnessDown) else {
            let message = "Failed to create media key events"
            logWarning(message)
            return .failed(message)
        }
        return .success
    }

    func switchBrowserTab(direction: BrowserTabDirection) -> SystemActionResult {
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: bundleIdentifier) else {
            return .unsupported("Frontmost app is not Safari, Chrome, or Edge")
        }

        guard let events = BrowserTabKeyEventFactory.events(for: direction) else {
            let message = "Failed to create browser tab key events"
            logWarning(message)
            return .failed(message)
        }

        for event in events {
            event.post(tap: .cghidEventTap)
        }
        return .success
    }

    func middleClick() -> SystemActionResult {
        middleClickEmitter.emitClick()
    }

    // MARK: - Private Helpers

    private func postMediaKey(_ key: MediaKey) -> Bool {
        guard let events = MediaKeyEventFactory.events(for: key) else { return false }
        for event in events {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }

    private func logWarning(_ message: String) {
        print("[SlidrFree] SystemControl: \(message)")
    }
}
