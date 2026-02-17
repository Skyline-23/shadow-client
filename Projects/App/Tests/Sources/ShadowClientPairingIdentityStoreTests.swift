import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Pairing identity store generates key material when provider has none")
func pairingIdentityStoreGeneratesMaterialWhenProviderFails() async throws {
    let suiteName = "ShadowClientPairingIdentityStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ShadowClientPairingIdentityStore(
        provider: FailingIdentityProvider(),
        defaults: defaults
    )

    let certificatePEMData = try await store.clientCertificatePEMData()
    let certificateSignature = try await store.clientCertificateSignature()
    let signedPayload = try await store.sign(Data("shadow-client".utf8))

    #expect(!certificatePEMData.isEmpty)
    #expect(!certificateSignature.isEmpty)
    #expect(!signedPayload.isEmpty)

    let storedCertificate = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM) ?? ""
    let storedPrivateKey = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM) ?? ""
    #expect(storedCertificate.contains("BEGIN CERTIFICATE"))
    #expect(storedPrivateKey.contains("BEGIN RSA PRIVATE KEY"))
}

@Test("Pairing identity store replaces invalid persisted key material")
func pairingIdentityStoreReplacesInvalidPersistedMaterial() async throws {
    let suiteName = "ShadowClientPairingIdentityStoreTests.invalid.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    defaults.set("broken-cert", forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM)
    defaults.set("broken-key", forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM)

    let store = ShadowClientPairingIdentityStore(
        provider: ShadowClientUserDefaultsIdentityProvider(defaults: defaults),
        defaults: defaults
    )

    let certificatePEMData = try await store.clientCertificatePEMData()
    #expect(!certificatePEMData.isEmpty)

    let replacedCertificate = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM) ?? ""
    let replacedPrivateKey = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM) ?? ""
    #expect(replacedCertificate.contains("BEGIN CERTIFICATE"))
    #expect(replacedPrivateKey.contains("BEGIN RSA PRIVATE KEY"))
    #expect(replacedCertificate != "broken-cert")
    #expect(replacedPrivateKey != "broken-key")
}

private struct FailingIdentityProvider: ShadowClientPairingIdentityProviding {
    func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial {
        throw ShadowClientGameStreamControlError.invalidKeyMaterial
    }
}
