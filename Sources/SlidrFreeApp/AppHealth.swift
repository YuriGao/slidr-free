import Foundation
import SlidrFreeCore

enum AppHealthState: String, CaseIterable, Equatable, Sendable {
    case ready
    case disabledByUser
    case noGesturesConfigured
    case setupRequired
    case permissionRequired
    case hardwareUnavailable
    case starting
    case degraded
    case recovering

    var localizationKey: String { "health_\(rawValue)" }

    var actionLocalizationKey: String? {
        switch self {
        case .ready: return nil
        case .disabledByUser: return "health_action_enable"
        case .noGesturesConfigured: return "health_action_configure_gestures"
        case .setupRequired: return "health_action_continue_setup"
        case .permissionRequired: return "health_action_grant_permission"
        case .hardwareUnavailable: return "health_action_view_compatibility"
        case .starting: return "health_action_recheck"
        case .degraded: return "health_action_view_fix"
        case .recovering: return nil
        }
    }
}

struct AppHealthInput: Equatable, Sendable {
    var settings: AppSettings
    var permission: PermissionState
    var frameworkAvailable: Bool?
    var deviceAvailable: Bool?
    var touchMonitor: TouchMonitorRuntimeState
    var eventTap: MouseButtonEventTapStatus
}

struct AppHealthResolver {
    func resolve(_ input: AppHealthInput) -> AppHealthState {
        if input.settings.experience.onboardingVersion < ExperienceSettings.currentOnboardingVersion {
            return .setupRequired
        }
        if !input.settings.isAppEnabled { return .disabledByUser }
        if !input.settings.hasConfiguredGesture { return .noGesturesConfigured }
        if input.permission != .granted { return .permissionRequired }
        if input.frameworkAvailable == false || input.deviceAvailable == false { return .hardwareUnavailable }
        if input.eventTap == .recoveryRequiresPipelineRestart { return .recovering }
        if input.touchMonitor == .unavailable ||
            (input.settings.middleClick.isEnabled && input.eventTap == .degraded) {
            return .degraded
        }
        if input.touchMonitor == .starting || input.touchMonitor == .stopped ||
            (input.settings.middleClick.isEnabled && input.eventTap == .starting) {
            return .starting
        }
        return .ready
    }
}

extension AppHealthResolver {
    func resolve(settings: AppSettings, permission: PermissionSnapshot, pipeline: InputPipelineStatus) -> AppHealthState {
        resolve(AppHealthInput(
            settings: settings,
            permission: permission.accessibility,
            frameworkAvailable: pipeline.frameworkAvailable,
            deviceAvailable: pipeline.deviceAvailable,
            touchMonitor: pipeline.touchMonitor,
            eventTap: pipeline.eventTap
        ))
    }
}
