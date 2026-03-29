import Foundation

public actor ShadowClientPairingRouteStore {
    private enum DefaultsKeys {
        static let persistentPreferredPairHosts = "pairing.routes.preferredHosts"
        static let persistentPreferredAuthorityHosts = "pairing.routes.preferredAuthorityHosts"
    }

    public static let shared = ShadowClientPairingRouteStore()

    private let defaults: UserDefaults
    private var persistentCached: [String: String]
    private var persistentAuthorityCached: [String: String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.persistentCached = Self.loadPersistentRoutes(from: defaults)
        self.persistentAuthorityCached = Self.loadPersistentAuthorityHosts(from: defaults)
    }

    public init(defaultsSuiteName: String) {
        if let suiteDefaults = UserDefaults(suiteName: defaultsSuiteName) {
            self.defaults = suiteDefaults
            self.persistentCached = Self.loadPersistentRoutes(from: suiteDefaults)
            self.persistentAuthorityCached = Self.loadPersistentAuthorityHosts(from: suiteDefaults)
        } else {
            self.defaults = .standard
            self.persistentCached = Self.loadPersistentRoutes(from: defaults)
            self.persistentAuthorityCached = Self.loadPersistentAuthorityHosts(from: defaults)
        }
    }

    public func preferredHost(for key: String) -> String? {
        persistentCached[Self.normalizeKey(key)]
    }

    public func setPreferredHost(_ host: String?, for key: String) {
        mutate(&persistentCached, host: host, key: key)
        defaults.set(persistentCached, forKey: DefaultsKeys.persistentPreferredPairHosts)
    }

    public func preferredAuthorityHost(for key: String) -> String? {
        persistentAuthorityCached[Self.normalizeKey(key)]
    }

    public func setPreferredAuthorityHost(_ host: String?, for key: String) {
        mutate(&persistentAuthorityCached, host: host, key: key)
        defaults.set(persistentAuthorityCached, forKey: DefaultsKeys.persistentPreferredAuthorityHosts)
    }

    private static func loadPersistentRoutes(from defaults: UserDefaults) -> [String: String] {
        let persisted = defaults.dictionary(forKey: DefaultsKeys.persistentPreferredPairHosts) as? [String: String] ?? [:]
        let filtered = persisted.reduce(into: [String: String]()) { partialResult, entry in
            let normalizedKey = normalizeKey(entry.key)
            guard normalizedKey.hasPrefix("uniqueid:") else {
                return
            }
            guard let normalizedHost = normalizeHost(entry.value) else {
                return
            }
            partialResult[normalizedKey] = normalizedHost
        }

        if filtered != persisted {
            defaults.set(filtered, forKey: DefaultsKeys.persistentPreferredPairHosts)
        }

        return filtered
    }

    private static func loadPersistentAuthorityHosts(from defaults: UserDefaults) -> [String: String] {
        let persisted = defaults.dictionary(forKey: DefaultsKeys.persistentPreferredAuthorityHosts) as? [String: String] ?? [:]
        let filtered = persisted.reduce(into: [String: String]()) { partialResult, entry in
            let normalizedKey = normalizeKey(entry.key)
            guard normalizedKey.hasPrefix("uniqueid:") else {
                return
            }
            guard let normalizedHost = normalizeHost(entry.value) else {
                return
            }
            partialResult[normalizedKey] = normalizedHost
        }

        if filtered != persisted {
            defaults.set(filtered, forKey: DefaultsKeys.persistentPreferredAuthorityHosts)
        }

        return filtered
    }

    private static func normalizeKey(_ key: String) -> String {
        key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizeHost(_ host: String?) -> String? {
        guard let host else {
            return nil
        }
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalizedHost.isEmpty ? nil : normalizedHost
    }

    private func mutate(_ storage: inout [String: String], host: String?, key: String) {
        let normalizedKey = Self.normalizeKey(key)
        guard !normalizedKey.isEmpty else {
            return
        }

        if let normalizedHost = Self.normalizeHost(host) {
            storage[normalizedKey] = normalizedHost
        } else {
            storage.removeValue(forKey: normalizedKey)
        }
    }
}
