import AppKit
import CoreGraphics

final class TrackpadCursorLock {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var origin: CGPoint = .zero
    private var locked = false

    func beginLock() {
        guard !locked else { return }
        locked = true

        origin = NSEvent.mouseLocation

        if let src = CGEventSource(stateID: .combinedSessionState) {
            src.localEventsSuppressionInterval = 0.07
        }

        CGWarpMouseCursorPosition(origin)

        installTap()
    }

    func endLock() {
        guard locked else { return }
        locked = false

        if let existingTap = tap {
            CGEvent.tapEnable(tap: existingTap, enable: false)
            CFMachPortInvalidate(existingTap)
            tap = nil
        }

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }

        if let src = CGEventSource(stateID: .combinedSessionState) {
            src.localEventsSuppressionInterval = 0.25
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let lock = Unmanaged<TrackpadCursorLock>.fromOpaque(userInfo).takeUnretainedValue()

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = lock.tap {
                CGEvent.tapEnable(tap: t, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if lock.locked {
            CGWarpMouseCursorPosition(lock.origin)
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    private func installTap() {
        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.rightMouseDragged.rawValue)
            | (1 << CGEventType.otherMouseDragged.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let newTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: selfPtr
        ) else {
            print("[SlidrFree] TrackpadCursorLock: Failed to create event tap")
            return
        }

        self.tap = newTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: newTap, enable: true)
    }
}
