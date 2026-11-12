import Foundation

@MainActor
final class AutoMutePreferences {
    private let defaults: UserDefaults
    private let enabledKey = "autoMuteEnabled"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: enabledKey) }
    }
}
