import Combine
import Foundation

public struct ShadowClientHostCustomizationSnapshot: Sendable {
    public let aliases: [String: String]
    public let notes: [String: String]
}

public actor ShadowClientHostCustomizationPersistence {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadSnapshot() -> ShadowClientHostCustomizationSnapshot {
        ShadowClientHostCustomizationSnapshot(
            aliases: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostAliases),
            notes: decodeMap(forKey: ShadowClientAppSettings.StorageKeys.hostNotes)
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
        }
    }

    public func alias(forHostID hostID: String) -> String {
        aliases[hostID] ?? ""
    }

    public func note(forHostID hostID: String) -> String {
        notes[hostID] ?? ""
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
}
