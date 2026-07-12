import Foundation
import SlidrFreeCore

final class SettingsStore: ObservableObject {
    static let defaultsKey = "SlidrFree.settings.v1"

    @Published private(set) var settings: AppSettings
    private(set) var lastLoadDiagnostic: String?

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.defaultsKey) {
            do {
                settings = try decoder.decode(AppSettings.self, from: data).validated()
            } catch {
                settings = .default.validated()
                lastLoadDiagnostic = "Stored settings could not be decoded; defaults restored."
            }
        } else {
            settings = .default.validated()
        }
    }

    func save(_ settings: AppSettings) {
        let validated = settings.validated()
        self.settings = validated

        if let data = try? encoder.encode(validated) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
