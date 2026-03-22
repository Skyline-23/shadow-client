import Foundation
import Testing
@testable import ShadowClientFeatureHome

@MainActor
@Test("Host customization kit binds friendly name note WOL fields and Apollo credentials through the store")
func hostCustomizationKitBindingsRoundTrip() async {
    let suiteName = "ShadowClientHostCustomizationKitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let persistence = ShadowClientHostCustomizationPersistence(defaults: defaults)
    let store = ShadowClientHostCustomizationStore(persistence: persistence)
    let host = ShadowClientRemoteHostDescriptor(
        host: "desktop.example",
        displayName: "Desktop",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "ONLINE",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        lastError: nil
    )

    let friendlyName = ShadowClientHostCustomizationKit.friendlyNameBinding(store: store, host: host)
    let notes = ShadowClientHostCustomizationKit.notesBinding(store: store, host: host)
    let wakeMAC = ShadowClientHostCustomizationKit.wakeOnLANMACAddressBinding(store: store, host: host)
    let wakePort = ShadowClientHostCustomizationKit.wakeOnLANPortBinding(store: store, host: host)
    let username = ShadowClientHostCustomizationKit.apolloAdminUsernameBinding(store: store, host: host)
    let password = ShadowClientHostCustomizationKit.apolloAdminPasswordBinding(store: store, host: host)

    friendlyName.wrappedValue = "Desk"
    notes.wrappedValue = "Main room"
    wakeMAC.wrappedValue = "aa-bb-cc-dd-ee-ff"
    wakePort.wrappedValue = "7"
    username.wrappedValue = "apollo"
    password.wrappedValue = "secret"

    #expect(ShadowClientHostCustomizationKit.friendlyName(store: store, host: host) == "Desk")
    #expect(ShadowClientHostCustomizationKit.notes(store: store, host: host) == "Main room")
    #expect(ShadowClientHostCustomizationKit.wakeOnLANMACAddress(store: store, host: host) == "AA-BB-CC-DD-EE-FF")
    #expect(ShadowClientHostCustomizationKit.wakeOnLANPort(store: store, host: host) == "7")
    #expect(ShadowClientHostCustomizationKit.apolloAdminUsername(store: store, host: host) == "apollo")
    #expect(ShadowClientHostCustomizationKit.apolloAdminPassword(store: store, host: host) == "secret")
}
