import SwiftUI
import SlidrFreeCore

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var permissionManager: PermissionManager
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Enable app", isOn: binding(\.isAppEnabled))
                Toggle("Launch at login", isOn: launchAtLoginBinding)
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Edge Gestures") {
                Toggle("Volume edge gesture", isOn: binding(\.features.volumeEdgeGesture))
                Toggle("Brightness edge gesture", isOn: binding(\.features.brightnessEdgeGesture))
                Toggle("Swap sides", isOn: binding(\.features.swapSides))
                Toggle("Bottom quarter only", isOn: binding(\.features.bottomQuarterOnly))
                labeledSlider("Edge width", value: binding(\.gesture.edgeWidthPercent), range: 0.04...0.20, isPercent: true)
                labeledSlider("Sensitivity", value: binding(\.gesture.sensitivity), range: 0.10...4.0)
                labeledSlider("Normal step", value: binding(\.gesture.normalStep), range: 0.10...10.0)
                labeledSlider("Fine step", value: binding(\.gesture.fineStep), range: 0.05...store.settings.gesture.normalStep)
            }

            Section("Clicks") {
                Toggle("Middle click", isOn: binding(\.features.middleClick))
                Toggle("Fine control", isOn: binding(\.features.fineControl))
            }

            Section("Safety") {
                Toggle("Smart typing detection", isOn: binding(\.features.smartTypingDetection))
                Toggle("Cursor freeze", isOn: binding(\.features.cursorFreeze))
                labeledSlider("Typing cooldown", value: binding(\.gesture.typingCooldownSeconds), range: 0.0...2.0, suffix: "s")
                labeledSlider("Continuous window", value: binding(\.gesture.continuousWindowSeconds), range: 0.05...1.0, suffix: "s")
            }

            Section("Permissions") {
                statusRow("Accessibility", value: permissionManager.snapshot.accessibility.rawValue)
                statusRow("Input Monitoring", value: permissionManager.snapshot.inputMonitoring.rawValue)
                statusRow("Can listen", value: permissionManager.snapshot.canListen ? "granted" : "denied")
                HStack {
                    Button("Prompt for Accessibility") {
                        permissionManager.promptForAccessibility()
                    }
                    Button("Open Privacy Settings") {
                        permissionManager.openPrivacySettings()
                    }
                    Button("Refresh") {
                        permissionManager.currentSnapshot()
                    }
                }
                Text("Input Monitoring may require enabling Slidr-Free in System Settings before event listening can start.")
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
                    launchAtLoginError = "Could not update launch at login: \(error.localizedDescription)"
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
}
