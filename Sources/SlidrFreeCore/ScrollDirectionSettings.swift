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

    /// When set, the vertical delta is replaced by exactly this many lines
    /// instead of being scaled by macOS wheel acceleration. The sign follows
    /// the incoming scroll, flipped by `invertsVertical`.
    public let uniformLines: Int?

    public init(invertsVertical: Bool, invertsHorizontal: Bool, uniformLines: Int? = nil) {
        self.invertsVertical = invertsVertical
        self.invertsHorizontal = invertsHorizontal
        self.uniformLines = uniformLines
    }

    public var isIdentity: Bool { !invertsVertical && !invertsHorizontal && uniformLines == nil }
}

/// Independent scroll-direction rules for trackpad-class and wheel-class
/// devices. Every flag is relative to whatever macOS is currently doing: an
/// enabled flag makes that device class scroll opposite to the system setting.
public struct ScrollDirectionSettings: Codable, Equatable, Sendable {
    public static let linesPerNotchRange = 1...10
    public static let defaultLinesPerNotch = 3

    public var invertTrackpad: Bool
    public var invertMouseWheel: Bool
    public var invertHorizontal: Bool
    /// Replaces the accelerated wheel delta with a fixed number of lines per
    /// notch. macOS scales wheel deltas with rotation speed, so a slow notch
    /// and a fast notch travel different distances; this rule removes that.
    public var uniformWheel: Bool
    public var linesPerNotch: Int {
        didSet { linesPerNotch = Self.validatedLinesPerNotch(linesPerNotch) }
    }

    public static let `default` = ScrollDirectionSettings(
        invertTrackpad: false,
        invertMouseWheel: false,
        invertHorizontal: false,
        uniformWheel: false
    )

    private enum CodingKeys: String, CodingKey {
        case invertTrackpad
        case invertMouseWheel
        case invertHorizontal
        case uniformWheel
        case linesPerNotch
    }

    public init(
        invertTrackpad: Bool = false,
        invertMouseWheel: Bool = false,
        invertHorizontal: Bool = false,
        uniformWheel: Bool = false,
        linesPerNotch: Int = ScrollDirectionSettings.defaultLinesPerNotch
    ) {
        self.invertTrackpad = invertTrackpad
        self.invertMouseWheel = invertMouseWheel
        self.invertHorizontal = invertHorizontal
        self.uniformWheel = uniformWheel
        self.linesPerNotch = Self.validatedLinesPerNotch(linesPerNotch)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            invertTrackpad: try container.decodeIfPresent(Bool.self, forKey: .invertTrackpad) ?? false,
            invertMouseWheel: try container.decodeIfPresent(Bool.self, forKey: .invertMouseWheel) ?? false,
            invertHorizontal: try container.decodeIfPresent(Bool.self, forKey: .invertHorizontal) ?? false,
            uniformWheel: try container.decodeIfPresent(Bool.self, forKey: .uniformWheel) ?? false,
            linesPerNotch: try container.decodeIfPresent(Int.self, forKey: .linesPerNotch) ?? Self.defaultLinesPerNotch
        )
    }

    public static func validatedLinesPerNotch(_ value: Int) -> Int {
        min(max(value, linesPerNotchRange.lowerBound), linesPerNotchRange.upperBound)
    }

    /// True when any rule would rewrite wheel or trackpad scroll events, which
    /// is what arms the scroll Event Tap.
    public var isActive: Bool { invertTrackpad || invertMouseWheel || uniformWheel }

    public func decision(for event: ScrollEventClassification) -> ScrollDirectionDecision {
        guard event.hasDelta else { return .identity }
        let kind = event.deviceKind
        let invertsDevice = kind == .trackpad ? invertTrackpad : invertMouseWheel
        // Uniform stepping only makes sense for notch hardware; continuous
        // trackpad streams are already pixel-accurate per frame.
        let uniformLines = kind == .mouse && uniformWheel && event.verticalDelta != 0
            ? linesPerNotch
            : nil
        guard invertsDevice || uniformLines != nil else { return .identity }
        return ScrollDirectionDecision(
            invertsVertical: invertsDevice,
            invertsHorizontal: invertsDevice && invertHorizontal,
            uniformLines: uniformLines
        )
    }
}
