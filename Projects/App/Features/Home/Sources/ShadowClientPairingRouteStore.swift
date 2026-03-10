import Foundation

public actor ShadowClientPairingRouteStore {
    private enum DefaultsKeys {
        static let preferredPairHosts = "pairing.routes.preferredHosts"
    }

    public static let shared = ShadowClientPairingRouteStore()

    private let defaults: UserDefaults
    private var cached: [String: String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cached = defaults.dictionary(forKey: DefaultsKeys.preferredPairHosts) as? [String: String] ?? [:]
    }

    public init(defaultsSuiteName: String) {
        if let suiteDefaults = UserDefaults(suiteName: defaultsSuiteName) {
            self.defaults = suiteDefaults
            self.cached = suiteDefaults.dictionary(forKey: DefaultsKeys.preferredPairHosts) as? [String: String] ?? [:]
        } else {
            self.defaults = .standard
            self.cached = defaults.dictionary(forKey: DefaultsKeys.preferredPairHosts) as? [String: String] ?? [:]
        }
    }

    public func preferredHost(for key: String) -> String? {
        cached[key]
    }

    public func setPreferredHost(_ host: String?, for key: String) {
        let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedKey.isEmpty else {
            return
        }

        if let host, !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            cached[normalizedKey] = host
        } else {
            cached.removeValue(forKey: normalizedKey)
        }

        defaults.set(cached, forKey: DefaultsKeys.preferredPairHosts)
    }
}
