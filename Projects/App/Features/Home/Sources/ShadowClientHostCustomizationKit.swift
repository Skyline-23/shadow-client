import SwiftUI

@MainActor
struct ShadowClientHostCustomizationKit {
    static func friendlyName(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.alias(forHostID: host.id)
    }

    static func notes(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.note(forHostID: host.id)
    }

    static func wakeOnLANMACAddress(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        let stored = store.wakeOnLANMACAddress(forHostID: host.id)
        if !stored.isEmpty {
            return stored
        }
        return host.macAddress ?? ""
    }

    static func wakeOnLANPort(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.wakeOnLANPort(forHostID: host.id)
    }

    static func lumenAdminUsername(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.lumenAdminUsername(forHostID: host.id)
    }

    static func lumenAdminPassword(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.lumenAdminPassword(forHostID: host.id)
    }

    static func friendlyNameBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { friendlyName(store: store, host: host) },
            set: { store.setAlias($0, forHostID: host.id) }
        )
    }

    static func notesBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { notes(store: store, host: host) },
            set: { store.setNote($0, forHostID: host.id) }
        )
    }

    static func wakeOnLANMACAddressBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { wakeOnLANMACAddress(store: store, host: host) },
            set: { store.setWakeOnLANMACAddress($0, forHostID: host.id) }
        )
    }

    static func wakeOnLANPortBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { wakeOnLANPort(store: store, host: host) },
            set: { store.setWakeOnLANPort($0, forHostID: host.id) }
        )
    }

    static func lumenAdminUsernameBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { lumenAdminUsername(store: store, host: host) },
            set: { store.setLumenAdminUsername($0, forHostID: host.id) }
        )
    }

    static func lumenAdminPasswordBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { lumenAdminPassword(store: store, host: host) },
            set: { store.setLumenAdminPassword($0, forHostID: host.id) }
        )
    }
}
