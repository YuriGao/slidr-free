import AppKit
import CoreGraphics
import IOKit
import SlidrFreeCore

// MARK: - Protocol

public protocol SystemControlling: AnyObject {
    func adjustVolume(delta: Double)
    func adjustBrightness(delta: Double)
    func middleClick(x: Double, y: Double)
    func freezeCursor(at point: CGPoint)
    func unfreezeCursor()
    func showFeedback(kind: FeedbackKind)
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

    func adjustVolume(delta: Double) {
        let isUp = delta > 0
        postMediaKey(keyCode: isUp ? NX_KEYTYPE_SOUND_UP : NX_KEYTYPE_SOUND_DOWN)
        showFeedback(kind: isUp ? .volumeUp : .volumeDown)
    }

    func adjustBrightness(delta: Double) {
        guard let service = displayService() else {
            logWarning("Failed to get display service for brightness adjustment")
            showFeedback(kind: delta > 0 ? .brightnessUp : .brightnessDown)
            return
        }
        defer { IOObjectRelease(service) }

        var current: Float = 0.5
        let readResult = IODisplayGetFloatParameter(service, 0, "brightness" as CFString, &current)
        guard readResult == KERN_SUCCESS else {
            logWarning("Failed to read brightness: \(readResult)")
            showFeedback(kind: delta > 0 ? .brightnessUp : .brightnessDown)
            return
        }

        let newBrightness = min(max(current + Float(delta) * 0.05, 0.0), 1.0)
        let setResult = IODisplaySetFloatParameter(service, 0, "brightness" as CFString, newBrightness)
        if setResult != KERN_SUCCESS {
            logWarning("Failed to set brightness: \(setResult)")
        }
        showFeedback(kind: delta > 0 ? .brightnessUp : .brightnessDown)
    }

    func middleClick(x: Double, y: Double) {
        let point = CGPoint(x: x, y: y)
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

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
        showFeedback(kind: .middleClick)
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

    func showFeedback(kind: FeedbackKind) {
        DispatchQueue.main.async { [weak self] in
            self?.showFeedbackOverlay(kind: kind)
        }
    }

    // MARK: - Private Helpers

    private func postMediaKey(keyCode: UInt16) {
        // Post key down event via CGEvent
        if let downEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) {
            downEvent.flags = CGEventFlags.maskNonCoalesced
            downEvent.post(tap: .cghidEventTap)
        }
        // Post key up event
        if let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            upEvent.flags = CGEventFlags.maskNonCoalesced
            upEvent.post(tap: .cghidEventTap)
        }
    }

    private func displayService() -> io_service_t? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IODisplayConnect")
        )
        return service != 0 ? service : nil
    }

    private func showFeedbackOverlay(kind: FeedbackKind) {
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

        let textField = NSTextField(labelWithString: label)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.feedbackWindow?.orderOut(nil)
            self?.feedbackWindow = nil
        }
    }

    private func logWarning(_ message: String) {
        print("[SlidrFree] SystemControl: \(message)")
    }
}

// MARK: - NX Key Constants

private let NX_KEYTYPE_SOUND_UP: UInt16 = 0
private let NX_KEYTYPE_SOUND_DOWN: UInt16 = 1
