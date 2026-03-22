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

    static func apolloAdminUsername(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.apolloAdminUsername(forHostID: host.id)
    }

    static func apolloAdminPassword(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> String {
        store.apolloAdminPassword(forHostID: host.id)
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

    static func apolloAdminUsernameBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { apolloAdminUsername(store: store, host: host) },
            set: { store.setApolloAdminUsername($0, forHostID: host.id) }
        )
    }

    static func apolloAdminPasswordBinding(
        store: ShadowClientHostCustomizationStore,
        host: ShadowClientRemoteHostDescriptor
    ) -> Binding<String> {
        Binding(
            get: { apolloAdminPassword(store: store, host: host) },
            set: { store.setApolloAdminPassword($0, forHostID: host.id) }
        )
    }
}
