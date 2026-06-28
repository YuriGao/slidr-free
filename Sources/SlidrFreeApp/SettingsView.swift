import SwiftUI
import SlidrFreeCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissionManager: PermissionManager
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
                Toggle(NSLocalizedString("volume_edge_gesture", comment: ""), isOn: binding(\.features.volumeEdgeGesture))
                Toggle(NSLocalizedString("brightness_edge_gesture", comment: ""), isOn: binding(\.features.brightnessEdgeGesture))
                Toggle(NSLocalizedString("swap_sides", comment: ""), isOn: binding(\.features.swapSides))
                Toggle(NSLocalizedString("bottom_quarter_only", comment: ""), isOn: binding(\.features.bottomQuarterOnly))
                labeledSlider(NSLocalizedString("edge_width", comment: ""), value: binding(\.gesture.edgeWidthPercent), range: 0.04...0.20, isPercent: true)
                labeledSlider(NSLocalizedString("sensitivity", comment: ""), value: binding(\.gesture.sensitivity), range: 0.10...4.0)
                labeledSlider(NSLocalizedString("normal_step", comment: ""), value: binding(\.gesture.normalStep), range: 0.10...10.0)
                labeledSlider(NSLocalizedString("fine_step", comment: ""), value: binding(\.gesture.fineStep), range: 0.05...store.settings.gesture.normalStep)
            }

            Section(NSLocalizedString("section_clicks", comment: "")) {
                Toggle(NSLocalizedString("middle_click", comment: ""), isOn: binding(\.features.middleClick))
                Toggle(NSLocalizedString("fine_control", comment: ""), isOn: binding(\.features.fineControl))
            }

            Section(NSLocalizedString("section_safety", comment: "")) {
                Toggle(NSLocalizedString("smart_typing_detection", comment: ""), isOn: binding(\.features.smartTypingDetection))
                Toggle(NSLocalizedString("cursor_freeze", comment: ""), isOn: binding(\.features.cursorFreeze))
                labeledSlider(NSLocalizedString("typing_cooldown", comment: ""), value: binding(\.gesture.typingCooldownSeconds), range: 0.0...2.0, suffix: "s")
                labeledSlider(NSLocalizedString("continuous_window", comment: ""), value: binding(\.gesture.continuousWindowSeconds), range: 0.05...1.0, suffix: "s")
            }

            Section(NSLocalizedString("section_permissions", comment: "")) {
                statusRow(NSLocalizedString("accessibility", comment: ""), value: localizedPermissionState(permissionManager.snapshot.accessibility))
                statusRow(NSLocalizedString("input_monitoring", comment: ""), value: localizedPermissionState(permissionManager.snapshot.inputMonitoring))
                statusRow(NSLocalizedString("can_listen", comment: ""), value: permissionManager.snapshot.canListen ? NSLocalizedString("granted", comment: "") : NSLocalizedString("denied", comment: ""))
                HStack {
                    Button(NSLocalizedString("open_accessibility_settings", comment: "")) {
                        permissionManager.openAccessibilitySettings()
                    }
                    Button(NSLocalizedString("open_input_monitoring_settings", comment: "")) {
                        permissionManager.openInputMonitoringSettings()
                    }
                    Button(NSLocalizedString("refresh", comment: "")) {
                        permissionManager.currentSnapshot()
                    }
                }
                Text(NSLocalizedString("input_monitoring_hint", comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}
