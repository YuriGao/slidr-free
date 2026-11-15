import Foundation

/// Hardware class behind a scroll-wheel event.
///
/// macOS exposes one shared "Natural scrolling" switch for every pointing
/// device, so a trackpad and a wheel mouse cannot disagree. Slidr Free can only
/// invert one class at a time, which makes the split itself part of the
/// behavior contract.
public enum ScrollDeviceKind: String, Codable, CaseIterable, Equatable, Sendable {
    /// Devices that stream pixel deltas and report gesture phases: the built-in
    /// trackpad and the Magic Mouse.
    case trackpad
    /// Notch-based wheel hardware that reports discrete deltas.
    case mouse
}

/// The subset of a `scrollWheel` event that decides which direction rule
/// applies. Deliberately free of CoreGraphics so the decision stays testable
/// without an event tap.
public struct ScrollEventClassification: Equatable, Sendable {
    public var isContinuous: Bool
    public var scrollPhase: Int
    public var momentumPhase: Int
    public var verticalDelta: Int64
    public var horizontalDelta: Int64

    public init(
        isContinuous: Bool,
        scrollPhase: Int = 0,
        momentumPhase: Int = 0,
        verticalDelta: Int64 = 0,
        horizontalDelta: Int64 = 0
    ) {
        self.isContinuous = isContinuous
        self.scrollPhase = scrollPhase
        self.momentumPhase = momentumPhase
        self.verticalDelta = verticalDelta
        self.horizontalDelta = horizontalDelta
    }

    /// Gesture and momentum phases only exist on devices that stream deltas, so
    /// either one is treated as evidence of a trackpad-class device even when a
    /// driver reports `isContinuous` as false.
    public var deviceKind: ScrollDeviceKind {
        if isContinuous || scrollPhase != 0 || momentumPhase != 0 { return .trackpad }
        return .mouse
    }

    /// Phase-only frames carry no movement; inverting them would be a no-op and
    /// is reported as such so callers can pass the event through untouched.
    public var hasDelta: Bool { verticalDelta != 0 || horizontalDelta != 0 }
}

public struct ScrollDirectionDecision: Equatable, Sendable {
    public static let identity = ScrollDirectionDecision(invertsVertical: false, invertsHorizontal: false)

    public let invertsVertical: Bool
    public let invertsHorizontal: Bool

    public init(invertsVertical: Bool, invertsHorizontal: Bool) {
        self.invertsVertical = invertsVertical
        self.invertsHorizontal = invertsHorizontal
    }

    public var isIdentity: Bool { !invertsVertical && !invertsHorizontal }
}

/// Independent scroll-direction rules for trackpad-class and wheel-class
/// devices. Every flag is relative to whatever macOS is currently doing: an
/// enabled flag makes that device class scroll opposite to the system setting.
public struct ScrollDirectionSettings: Codable, Equatable, Sendable {
    public var invertTrackpad: Bool
    public var invertMouseWheel: Bool
    public var invertHorizontal: Bool

    public static let `default` = ScrollDirectionSettings(
        invertTrackpad: false,
        invertMouseWheel: false,
        invertHorizontal: false
    )

    private enum CodingKeys: String, CodingKey {
        case invertTrackpad
        case invertMouseWheel
        case invertHorizontal
    }

    public init(invertTrackpad: Bool = false, invertMouseWheel: Bool = false, invertHorizontal: Bool = false) {
        self.invertTrackpad = invertTrackpad
        self.invertMouseWheel = invertMouseWheel
        self.invertHorizontal = invertHorizontal
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            invertTrackpad: try container.decodeIfPresent(Bool.self, forKey: .invertTrackpad) ?? false,
            invertMouseWheel: try container.decodeIfPresent(Bool.self, forKey: .invertMouseWheel) ?? false,
            invertHorizontal: try container.decodeIfPresent(Bool.self, forKey: .invertHorizontal) ?? false
        )
    }

    /// True when at least one device class is inverted, which is what arms the
    /// scroll Event Tap.
    public var isActive: Bool { invertTrackpad || invertMouseWheel }

    public func decision(for event: ScrollEventClassification) -> ScrollDirectionDecision {
        guard event.hasDelta else { return .identity }
        let invertsDevice = event.deviceKind == .trackpad ? invertTrackpad : invertMouseWheel
        guard invertsDevice else { return .identity }
        return ScrollDirectionDecision(invertsVertical: true, invertsHorizontal: invertHorizontal)
    }
}
