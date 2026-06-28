import AppKit

enum MediaKey {
    case volumeUp
    case volumeDown
    case brightnessUp
    case brightnessDown

    fileprivate var nxKeyType: Int32 {
        switch self {
        case .volumeUp: return 0
        case .volumeDown: return 1
        case .brightnessUp: return 2
        case .brightnessDown: return 3
        }
    }
}

enum MediaKeyEventFactory {
    private static let auxiliaryControlButtonSubtype: Int16 = 8
    private static let keyDownState: Int32 = 0xA
    private static let keyUpState: Int32 = 0xB

    static func events(for key: MediaKey) -> [NSEvent]? {
        guard let down = event(for: key, state: keyDownState),
              let up = event(for: key, state: keyUpState) else {
            return nil
        }
        return [down, up]
    }

    private static func event(for key: MediaKey, state: Int32) -> NSEvent? {
        NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: auxiliaryControlButtonSubtype,
            data1: Int((key.nxKeyType << 16) | (state << 8)),
            data2: -1
        )
    }
}
