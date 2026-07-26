import AppKit
import CoreGraphics
import SlidrFreeCore

// MARK: - Protocol

public protocol SystemControlling: AnyObject {
    func adjustVolume(delta: Double) -> SystemActionResult
    func adjustBrightness(delta: Double) -> SystemActionResult
    func switchBrowserTab(direction: BrowserTabDirection, wrapsAround: Bool) -> SystemActionResult
    func activateOrMinimizeApplication(_ binding: ApplicationBinding) -> SystemActionResult
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
    private let frontmostApplicationProvider: () -> FrontmostApplicationIdentity?
    private let applicationWindowToggler: (pid_t) -> Bool
    private let applicationURLResolver: (String) -> URL?
    private let applicationOpener: (URL) -> Bool
    private let browserTabStateProvider: (String) -> BrowserTabState?
    private let browserTabEventPoster: (BrowserTabDirection) -> Bool

    init(
        middleClickEmitter: any MiddleClickEmitting = MiddleClickEmitter(),
        frontmostApplicationProvider: @escaping () -> FrontmostApplicationIdentity? = {
            guard let application = NSWorkspace.shared.frontmostApplication else { return nil }
            return FrontmostApplicationIdentity(
                bundleIdentifier: application.bundleIdentifier,
                processIdentifier: application.processIdentifier
            )
        },
        applicationWindowToggler: @escaping (pid_t) -> Bool = {
            ApplicationWindowController.toggleFrontWindow(processIdentifier: $0)
        },
        applicationURLResolver: @escaping (String) -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        },
        applicationOpener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        browserTabStateProvider: @escaping (String) -> BrowserTabState? = {
            BrowserTabStateProvider.state(bundleIdentifier: $0)
        },
        browserTabEventPoster: @escaping (BrowserTabDirection) -> Bool = { direction in
            guard let events = BrowserTabKeyEventFactory.events(for: direction) else { return false }
            events.forEach { $0.post(tap: .cghidEventTap) }
            return true
        }
    ) {
        self.middleClickEmitter = middleClickEmitter
        self.frontmostApplicationProvider = frontmostApplicationProvider
        self.applicationWindowToggler = applicationWindowToggler
        self.applicationURLResolver = applicationURLResolver
        self.applicationOpener = applicationOpener
        self.browserTabStateProvider = browserTabStateProvider
        self.browserTabEventPoster = browserTabEventPoster
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

    func switchBrowserTab(direction: BrowserTabDirection, wrapsAround: Bool) -> SystemActionResult {
        let bundleIdentifier = frontmostApplicationProvider()?.bundleIdentifier
        guard BrowserTabKeyEventFactory.isSupportedBrowser(bundleIdentifier: bundleIdentifier) else {
            return .unsupported("Frontmost app is not Safari, Chrome, or Edge")
        }

        if !wrapsAround {
            guard let bundleIdentifier,
                  let state = browserTabStateProvider(bundleIdentifier) else {
                let message = "Browser tab boundary could not be determined"
                logWarning(message)
                return .failed(message)
            }
            guard state.permitsSwitch(direction) else {
                return .unsupported("Browser tab is already at the boundary")
            }
        }

        guard browserTabEventPoster(direction) else {
            let message = "Failed to create browser tab key events"
            logWarning(message)
            return .failed(message)
        }

        return .success
    }

    func middleClick() -> SystemActionResult {
        middleClickEmitter.emitClick()
    }

    func activateOrMinimizeApplication(_ binding: ApplicationBinding) -> SystemActionResult {
        if let frontmost = frontmostApplicationProvider(),
           frontmost.bundleIdentifier == binding.bundleIdentifier {
            guard applicationWindowToggler(frontmost.processIdentifier) else {
                let message = "Configured application window could not be toggled"
                logWarning(message)
                return .failed(message)
            }
            return .success
        }

        var candidates: [URL] = []
        if let resolved = applicationURLResolver(binding.bundleIdentifier) {
            candidates.append(resolved.standardizedFileURL)
        }
        if binding.applicationPath.hasPrefix("/"),
           URL(fileURLWithPath: binding.applicationPath).pathExtension.lowercased() == "app" {
            let fallback = URL(fileURLWithPath: binding.applicationPath).standardizedFileURL
            if !candidates.contains(fallback) { candidates.append(fallback) }
        }

        guard !candidates.isEmpty else {
            return .unsupported("Configured application is unavailable")
        }
        for candidate in candidates where applicationOpener(candidate) {
            return .success
        }

        let message = "Configured application could not be opened"
        logWarning(message)
        return .failed(message)
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
