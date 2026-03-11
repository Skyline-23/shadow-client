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
        defaultsSuiteName: suiteName
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

@Test("Pairing identity store creates TLS client credential from generated material")
func pairingIdentityStoreCreatesTLSClientCredential() async throws {
    let suiteName = "ShadowClientPairingIdentityStoreTests.credential.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ShadowClientPairingIdentityStore(
        provider: FailingIdentityProvider(),
        defaultsSuiteName: suiteName
    )

    let credential = try await store.tlsClientCertificateCredential()
    #expect(credential.identity != nil)
    #expect(!credential.certificates.isEmpty)
}

@Test("Pairing identity store creates TLS identity without persisting a key tag")
func pairingIdentityStoreCreatesTLSIdentityWithoutKeychainTag() async throws {
    let suiteName = "ShadowClientPairingIdentityStoreTests.identity.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ShadowClientPairingIdentityStore(
        provider: FailingIdentityProvider(),
        defaultsSuiteName: suiteName
    )

    let identity = try await store.tlsClientIdentity()
    withExtendedLifetime(identity) {}
    let persistedKeyTag = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.keyTag)
    #expect(persistedKeyTag == nil || persistedKeyTag?.isEmpty == true)
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

    let store = ShadowClientPairingIdentityStore(defaultsSuiteName: suiteName)

    let certificatePEMData = try await store.clientCertificatePEMData()
    #expect(!certificatePEMData.isEmpty)

    let replacedCertificate = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM) ?? ""
    let replacedPrivateKey = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM) ?? ""
    #expect(replacedCertificate.contains("BEGIN CERTIFICATE"))
    #expect(replacedPrivateKey.contains("BEGIN RSA PRIVATE KEY"))
    #expect(replacedCertificate != "broken-cert")
    #expect(replacedPrivateKey != "broken-key")
}

@Test("Pairing identity store replaces persisted certificate-key mismatch")
func pairingIdentityStoreReplacesMismatchedPersistedMaterial() async throws {
    let sourceSuiteA = "ShadowClientPairingIdentityStoreTests.mismatch.sourceA.\(UUID().uuidString)"
    let sourceSuiteB = "ShadowClientPairingIdentityStoreTests.mismatch.sourceB.\(UUID().uuidString)"
    let targetSuite = "ShadowClientPairingIdentityStoreTests.mismatch.target.\(UUID().uuidString)"

    guard
        let sourceDefaultsA = UserDefaults(suiteName: sourceSuiteA),
        let sourceDefaultsB = UserDefaults(suiteName: sourceSuiteB),
        let targetDefaults = UserDefaults(suiteName: targetSuite)
    else {
        Issue.record("Expected isolated defaults suites")
        return
    }

    defer {
        sourceDefaultsA.removePersistentDomain(forName: sourceSuiteA)
        sourceDefaultsB.removePersistentDomain(forName: sourceSuiteB)
        targetDefaults.removePersistentDomain(forName: targetSuite)
    }

    let sourceMaterialA = try await generatePersistedIdentityMaterial(
        suiteName: sourceSuiteA,
        defaults: sourceDefaultsA
    )
    let sourceMaterialB = try await generatePersistedIdentityMaterial(
        suiteName: sourceSuiteB,
        defaults: sourceDefaultsB
    )

    targetDefaults.set(sourceMaterialA.certificatePEM, forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM)
    targetDefaults.set(sourceMaterialB.privateKeyPEM, forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM)

    let store = ShadowClientPairingIdentityStore(defaultsSuiteName: targetSuite)

    _ = try await store.clientCertificatePEMData()

    let replacedCertificate = targetDefaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM) ?? ""
    let replacedPrivateKey = targetDefaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM) ?? ""

    #expect(replacedCertificate.contains("BEGIN CERTIFICATE"))
    #expect(replacedPrivateKey.contains("BEGIN RSA PRIVATE KEY"))
    #expect(!(replacedCertificate == sourceMaterialA.certificatePEM && replacedPrivateKey == sourceMaterialB.privateKeyPEM))
}

private func generatePersistedIdentityMaterial(
    suiteName: String,
    defaults: UserDefaults
) async throws -> ShadowClientPairingIdentityMaterial {
    let store = ShadowClientPairingIdentityStore(
        provider: FailingIdentityProvider(),
        defaultsSuiteName: suiteName
    )
    _ = try await store.clientCertificatePEMData()

    let certificate = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM) ?? ""
    let privateKey = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM) ?? ""

    #expect(certificate.contains("BEGIN CERTIFICATE"))
    #expect(privateKey.contains("BEGIN RSA PRIVATE KEY"))

    return .init(certificatePEM: certificate, privateKeyPEM: privateKey)
}

private struct FailingIdentityProvider: ShadowClientPairingIdentityProviding {
    func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial {
        throw ShadowClientGameStreamControlError.invalidKeyMaterial
    }
}
