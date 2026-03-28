import Combine
import Foundation

public struct ShadowClientHostCustomizationSnapshot: Sendable {
    public let aliases: [String: String]
    public let notes: [String: String]
    public let wakeOnLANMACAddresses: [String: String]
    public let wakeOnLANPorts: [String: String]
    public let lumenAdminUsernames: [String: String]
    public let lumenAdminPasswords: [String: String]
}

public actor ShadowClientHostCustomizationPersistence {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSnapshot() -> ShadowClientHostCustomizationSnapshot {
        ShadowClientHostCustomizationSnapshot(
            aliases: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostAliases),
            notes: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostNotes),
            wakeOnLANMACAddresses: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostWakeOnLANMACAddresses),
            wakeOnLANPorts: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostWakeOnLANPorts),
            lumenAdminUsernames: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.lumenAdminUsernames),
            lumenAdminPasswords: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.lumenAdminPasswords)
        )
    }

    public func saveAlias(_ value: String?, forHostID hostID: String) {
        var aliases = decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostAliases)
        if let value, !value.isEmpty {
            aliases[hostID] = value
        } else {
            aliases.removeValue(forKey: hostID)
        }
        persistMap(aliases, forKey: ShadowClientAppSettings.StorageKeys.hostAliases)
    }

    public func saveNote(_ value: String?, forHostID hostID: String) {
        var notes = decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostNotes)
        if let value, !value.isEmpty {
            notes[hostID] = value
        } else {
            notes.removeValue(forKey: hostID)
        }
        persistMap(notes, forKey: ShadowClientAppSettings.StorageKeys.hostNotes)
    }

    public func saveWakeOnLANMACAddress(_ value: String?, forHostID hostID: String) {
        var addresses = decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostWakeOnLANMACAddresses)
        if let value, !value.isEmpty {
            addresses[hostID] = value
        } else {
            addresses.removeValue(forKey: hostID)
        }
        persistMap(addresses, forKey: ShadowClientAppSettings.StorageKeys.hostWakeOnLANMACAddresses)
    }

    public func saveWakeOnLANPort(_ value: String?, forHostID hostID: String) {
        var ports = decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostWakeOnLANPorts)
        if let value, !value.isEmpty {
            ports[hostID] = value
        } else {
            ports.removeValue(forKey: hostID)
        }
        persistMap(ports, forKey: ShadowClientAppSettings.StorageKeys.hostWakeOnLANPorts)
    }

    public func saveLumenAdminUsername(_ value: String?, forHostID hostID: String) {
        var usernames = decodeMap(forKey: ShadowClientAppSettings.StorageKeys.lumenAdminUsernames)
        if let value, !value.isEmpty {
            usernames[hostID] = value
        } else {
            usernames.removeValue(forKey: hostID)
        }
        persistMap(usernames, forKey: ShadowClientAppSettings.StorageKeys.lumenAdminUsernames)
    }

    public func saveLumenAdminPassword(_ value: String?, forHostID hostID: String) {
        var passwords = decodeMap(forKey: ShadowClientAppSettings.StorageKeys.lumenAdminPasswords)
        if let value, !value.isEmpty {
            passwords[hostID] = value
        } else {
            passwords.removeValue(forKey: hostID)
        }
        persistMap(passwords, forKey: ShadowClientAppSettings.StorageKeys.lumenAdminPasswords)
    }

    public func removeHost(_ hostID: String) {
        saveAlias(nil, forHostID: hostID)
        saveNote(nil, forHostID: hostID)
        saveWakeOnLANMACAddress(nil, forHostID: hostID)
        saveWakeOnLANPort(nil, forHostID: hostID)
        saveLumenAdminUsername(nil, forHostID: hostID)
        saveLumenAdminPassword(nil, forHostID: hostID)
    }

    private func decodeMap(forKey key: String) -> [String: String] {
        guard
            let rawValue = defaults.string(forKey: key),
            let data = rawValue.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return decoded
    }

    private func persistMap(_ map: [String: String], forKey key: String) {
        guard let data = try? JSONEncoder().encode(map),
              let encoded = String(data: data, encoding: .utf8) else {
            defaults.removeObject(forKey: key)
            return
        }

        defaults.set(encoded, forKey: key)
    }
}

@MainActor
public final class ShadowClientHostCustomizationStore: ObservableObject {
    @Published private var aliases: [String: String] = [:]
    @Published private var notes: [String: String] = [:]
    @Published private var wakeOnLANMACAddresses: [String: String] = [:]
    @Published private var wakeOnLANPorts: [String: String] = [:]
    @Published private var lumenAdminUsernames: [String: String] = [:]
    @Published private var lumenAdminPasswords: [String: String] = [:]

    private let persistence: ShadowClientHostCustomizationPersistence

    public init(persistence: ShadowClientHostCustomizationPersistence = .init()) {
        self.persistence = persistence

        Task { [weak self] in
            guard let self else {
                return
            }

            let snapshot = await persistence.loadSnapshot()
            aliases = snapshot.aliases
            notes = snapshot.notes
            wakeOnLANMACAddresses = snapshot.wakeOnLANMACAddresses
            wakeOnLANPorts = snapshot.wakeOnLANPorts
            lumenAdminUsernames = snapshot.lumenAdminUsernames
            lumenAdminPasswords = snapshot.lumenAdminPasswords
        }
    }

    public func alias(forHostID hostID: String) -> String {
        aliases[hostID] ?? ""
    }

    public func note(forHostID hostID: String) -> String {
        notes[hostID] ?? ""
    }

    public func wakeOnLANMACAddress(forHostID hostID: String) -> String {
        wakeOnLANMACAddresses[hostID] ?? ""
    }

    public func wakeOnLANPort(forHostID hostID: String) -> String {
        wakeOnLANPorts[hostID] ?? ""
    }

    public func lumenAdminUsername(forHostID hostID: String) -> String {
        lumenAdminUsernames[hostID] ?? ""
    }

    public func lumenAdminPassword(forHostID hostID: String) -> String {
        lumenAdminPasswords[hostID] ?? ""
    }

    public func setAlias(_ value: String, forHostID hostID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            aliases.removeValue(forKey: hostID)
        } else {
            aliases[hostID] = value
        }

        Task {
            await persistence.saveAlias(trimmed.isEmpty ? nil : value, forHostID: hostID)
        }
    }

    public func setNote(_ value: String, forHostID hostID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeValue(forKey: hostID)
        } else {
            notes[hostID] = value
        }

        Task {
            await persistence.saveNote(trimmed.isEmpty ? nil : value, forHostID: hostID)
        }
    }

    public func setWakeOnLANMACAddress(_ value: String, forHostID hostID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let persistedValue = trimmed.uppercased()
        if persistedValue.isEmpty {
            wakeOnLANMACAddresses.removeValue(forKey: hostID)
        } else {
            wakeOnLANMACAddresses[hostID] = persistedValue
        }

        Task {
            await persistence.saveWakeOnLANMACAddress(
                persistedValue.isEmpty ? nil : persistedValue,
                forHostID: hostID
            )
        }
    }

    public func setWakeOnLANPort(_ value: String, forHostID hostID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            wakeOnLANPorts.removeValue(forKey: hostID)
        } else {
            wakeOnLANPorts[hostID] = trimmed
        }

        Task {
            await persistence.saveWakeOnLANPort(trimmed.isEmpty ? nil : trimmed, forHostID: hostID)
        }
    }

    public func setLumenAdminUsername(_ value: String, forHostID hostID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            lumenAdminUsernames.removeValue(forKey: hostID)
        } else {
            lumenAdminUsernames[hostID] = value
        }

        Task {
            await persistence.saveLumenAdminUsername(trimmed.isEmpty ? nil : value, forHostID: hostID)
        }
    }

    public func setLumenAdminPassword(_ value: String, forHostID hostID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            lumenAdminPasswords.removeValue(forKey: hostID)
        } else {
            lumenAdminPasswords[hostID] = value
        }

        Task {
            await persistence.saveLumenAdminPassword(trimmed.isEmpty ? nil : value, forHostID: hostID)
        }
    }

    public func removeHost(_ hostID: String) {
        aliases.removeValue(forKey: hostID)
        notes.removeValue(forKey: hostID)
        wakeOnLANMACAddresses.removeValue(forKey: hostID)
        wakeOnLANPorts.removeValue(forKey: hostID)
        lumenAdminUsernames.removeValue(forKey: hostID)
        lumenAdminPasswords.removeValue(forKey: hostID)

        Task {
            await persistence.removeHost(hostID)
        }
    }
}
