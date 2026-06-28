import AppKit
import CoreGraphics
import IOKit
import SlidrFreeCore

// MARK: - Protocol

public protocol SystemControlling: AnyObject {
    func adjustVolume(delta: Double) -> SystemActionResult
    func adjustBrightness(delta: Double) -> SystemActionResult
    func middleClick(x: Double, y: Double) -> SystemActionResult
    func freezeCursor(at point: CGPoint)
    func unfreezeCursor()
    func showFeedback(kind: FeedbackKind, message: String?) -> SystemActionResult
}

public enum SystemActionResult: Equatable {
    case success
    case failed(String)
    case unsupported(String)
}

public enum FeedbackKind: String {
    case volumeUp
    case volumeDown
    case brightnessUp
    case brightnessDown
    case middleClick
}

// MARK: - Concrete Implementation

final class SystemControl: SystemControlling {
    private var frozenPosition: CGPoint?
    private var feedbackWindow: NSWindow?

    func adjustVolume(delta: Double) -> SystemActionResult {
        let isUp = delta > 0
        guard postMediaKey(isUp ? .volumeUp : .volumeDown) else {
            let message = "Failed to create media key events"
            logWarning(message)
            _ = showFeedback(kind: isUp ? .volumeUp : .volumeDown, message: message)
            return .failed(message)
        }
        _ = showFeedback(kind: isUp ? .volumeUp : .volumeDown, message: nil)
        return .success
    }

    func adjustBrightness(delta: Double) -> SystemActionResult {
        guard let service = displayService() else {
            let message = "No built-in display service"
            logWarning(message)
            _ = showFeedback(kind: delta > 0 ? .brightnessUp : .brightnessDown, message: message)
            return .failed(message)
        }
        defer { IOObjectRelease(service) }

        var current: Float = 0.5
        let readResult = IODisplayGetFloatParameter(service, 0, "brightness" as CFString, &current)
        guard readResult == KERN_SUCCESS else {
            let message = "Failed to read brightness: \(readResult)"
            logWarning(message)
            _ = showFeedback(kind: delta > 0 ? .brightnessUp : .brightnessDown, message: message)
            return .failed(message)
        }

        let newBrightness = min(max(current + Float(delta) * 0.05, 0.0), 1.0)
        let setResult = IODisplaySetFloatParameter(service, 0, "brightness" as CFString, newBrightness)
        if setResult != KERN_SUCCESS {
            logWarning("Failed to set brightness: \(setResult)")
        }
        _ = showFeedback(kind: delta > 0 ? .brightnessUp : .brightnessDown, message: nil)
        return .success
    }

    func middleClick(x: Double, y: Double) -> SystemActionResult {
        let point = CGPoint(x: x, y: y)
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return .failed("Failed to create HID event source")
        }

        if let downEvent = CGEvent(
            mouseEventSource: source,
            mouseType: .otherMouseDown,
            mouseCursorPosition: point,
            mouseButton: .center
        ) {
            downEvent.post(tap: .cghidEventTap)
        }
        if let upEvent = CGEvent(
            mouseEventSource: source,
            mouseType: .otherMouseUp,
            mouseCursorPosition: point,
            mouseButton: .center
        ) {
            upEvent.post(tap: .cghidEventTap)
        }
        _ = showFeedback(kind: .middleClick, message: nil)
        return .success
    }

    func freezeCursor(at point: CGPoint) {
        frozenPosition = point
        CGAssociateMouseAndMouseCursorPosition(Int32(0))
        CGWarpMouseCursorPosition(point)
        DispatchQueue.main.async {
            NSCursor.hide()
        }
    }

    func unfreezeCursor() {
        CGAssociateMouseAndMouseCursorPosition(Int32(1))
        DispatchQueue.main.async {
            NSCursor.unhide()
        }
        frozenPosition = nil
    }

    func showFeedback(kind: FeedbackKind, message: String? = nil) -> SystemActionResult {
        DispatchQueue.main.async { [weak self] in
            self?.showFeedbackOverlay(kind: kind, message: message)
        }
        return .success
    }

    // MARK: - Private Helpers

    private func postMediaKey(_ key: MediaKey) -> Bool {
        guard let events = MediaKeyEventFactory.events(for: key) else { return false }
        for event in events {
            event.cgEvent?.post(tap: .cghidEventTap)
        }
        return true
    }

    private func displayService() -> io_service_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
        return service != 0 ? service : nil
    }

    private func showFeedbackOverlay(kind: FeedbackKind, message: String?) {
        // Dismiss existing overlay
        feedbackWindow?.orderOut(nil)
        feedbackWindow = nil

        let label: String = {
            switch kind {
            case .volumeUp: return "Vol +"
            case .volumeDown: return "Vol -"
            case .brightnessUp: return "Bright +"
            case .brightnessDown: return "Bright -"
            case .middleClick: return "Click"
            }
        }()

        let textField = NSTextField(labelWithString: message.map { "\(label)\n\($0)" } ?? label)
        textField.font = NSFont.systemFont(ofSize: 24, weight: .medium)
        textField.textColor = .white
        textField.alignment = .center

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 140, height: 50),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.65)
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.center()
        panel.contentView = textField
        panel.orderFront(nil)

        feedbackWindow = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self, weak panel] in
            guard let self, let panel, self.feedbackWindow === panel else { return }
            self.feedbackWindow?.orderOut(nil)
            self.feedbackWindow = nil
        }
    }

    private func logWarning(_ message: String) {
        print("[SlidrFree] SystemControl: \(message)")
    }
}
