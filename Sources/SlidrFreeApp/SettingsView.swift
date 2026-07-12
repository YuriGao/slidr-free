import SwiftUI
import SlidrFreeCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissionManager: PermissionManager
    @ObservedObject var pipelineStatus: InputPipelineStatus
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section(NSLocalizedString("section_general", comment: "")) {
                Toggle(NSLocalizedString("enable_app_toggle", comment: ""), isOn: binding(\.isAppEnabled))
                Toggle(NSLocalizedString("launch_at_login", comment: ""), isOn: launchAtLoginBinding)
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section(NSLocalizedString("section_edge_gestures", comment: "")) {
                Text(NSLocalizedString("physical_trackpad_experimental_warning", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(NSLocalizedString("volume_edge_gesture", comment: ""), isOn: binding(\.features.volumeEdgeGesture))
                Toggle(NSLocalizedString("brightness_edge_gesture", comment: ""), isOn: binding(\.features.brightnessEdgeGesture))
                Toggle(NSLocalizedString("browser_tab_edge_gesture", comment: ""), isOn: binding(\.features.browserTabEdgeGesture))
                Toggle(NSLocalizedString("swap_sides", comment: ""), isOn: binding(\.features.swapSides))
                labeledSlider(NSLocalizedString("edge_width", comment: ""), value: binding(\.gesture.edgeWidthPercent), range: 0.04...0.20, isPercent: true)
            }

            Section(NSLocalizedString("section_middle_click", comment: "")) {
                Toggle(NSLocalizedString("middle_click_enable", comment: ""), isOn: binding(\.middleClick.isEnabled))
                Toggle(NSLocalizedString("middle_click_tap_enable", comment: ""), isOn: binding(\.middleClick.tapEnabled))
                    .disabled(!store.settings.middleClick.isEnabled)
                Text(NSLocalizedString("middle_click_fixed_three", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(NSLocalizedString("middle_click_conflict_guidance", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                statusRow(NSLocalizedString("touch_monitor_status", comment: ""), value: localizedTouchState(pipelineStatus.touchMonitor))
                statusRow(NSLocalizedString("event_tap_status", comment: ""), value: localizedEventTapState(pipelineStatus.eventTap))
            }

            Section(NSLocalizedString("section_permissions", comment: "")) {
                statusRow(NSLocalizedString("accessibility", comment: ""), value: localizedPermissionState(permissionManager.snapshot.accessibility))
                statusRow(NSLocalizedString("can_listen", comment: ""), value: permissionManager.snapshot.canListen ? NSLocalizedString("granted", comment: "") : NSLocalizedString("denied", comment: ""))
                HStack {
                    Button(NSLocalizedString("open_accessibility_settings", comment: "")) {
                        permissionManager.openAccessibilitySettings()
                    }
                    Button(NSLocalizedString("refresh", comment: "")) {
                        permissionManager.currentSnapshot()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.settings[keyPath: keyPath] },
            set: { newValue in
                var updated = store.settings
                updated[keyPath: keyPath] = newValue
                store.save(updated)
            }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { store.settings.launchAtLogin },
            set: { newValue in
                do {
                    try permissionManager.setLaunchAtLogin(newValue)
                    var updated = store.settings
                    updated.launchAtLogin = newValue
                    store.save(updated)
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = String(format: NSLocalizedString("launch_at_login_error", comment: ""), error.localizedDescription)
                }
            }
        )
    }

    private func labeledSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, isPercent: Bool = false, suffix: String = "") -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text(sliderValueText(value.wrappedValue, isPercent: isPercent, suffix: suffix))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func sliderValueText(_ value: Double, isPercent: Bool, suffix: String) -> String {
        if isPercent {
            return value.formatted(.percent.precision(.fractionLength(0)))
        }

        return value.formatted(.number.precision(.fractionLength(2))) + suffix
    }

    private func statusRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }

    private func localizedPermissionState(_ state: PermissionState) -> String {
        NSLocalizedString(state.rawValue, comment: "")
    }

    private func localizedTouchState(_ state: TouchMonitorRuntimeState) -> String {
        NSLocalizedString("pipeline_\(state.rawValue)", comment: "")
    }

    private func localizedEventTapState(_ state: MouseButtonEventTapStatus) -> String {
        switch state {
        case .stopped: return NSLocalizedString("pipeline_stopped", comment: "")
        case .starting: return NSLocalizedString("pipeline_starting", comment: "")
        case .running: return NSLocalizedString("pipeline_running", comment: "")
        case .recoveryRequiresPipelineRestart: return NSLocalizedString("pipeline_restarting", comment: "")
        case .degraded: return NSLocalizedString("pipeline_degraded", comment: "")
        }
    }
}
