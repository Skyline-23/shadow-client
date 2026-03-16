import CommonCrypto
import CryptoKit
import Foundation
import Network
import os
import Security
import ShadowClientFeatureConnection
import ShadowClientFeatureSession

public enum ShadowClientRemotePairingState: Equatable, Sendable {
    case idle
    case pairing(host: String, pin: String)
    case paired(String)
    case failed(String)
}

public extension ShadowClientRemotePairingState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case let .pairing(host, _):
            return "Pairing with \(host). Enter displayed PIN in Apollo."
        case let .paired(message):
            return message
        case let .failed(message):
            return "Failed - \(message)"
        }
    }

    var activePIN: String? {
        switch self {
        case let .pairing(_, pin):
            return pin
        case .idle, .paired, .failed:
            return nil
        }
    }

    var isInProgress: Bool {
        switch self {
        case .pairing:
            return true
        case .idle, .paired, .failed:
            return false
        }
    }
}

public struct ShadowClientGameStreamPairingResult: Equatable, Sendable {
    public let host: String

    public init(host: String) {
        self.host = host
    }
}

public struct ShadowClientPairingIdentityMaterial: Equatable, Sendable {
    public let certificatePEM: String
    public let privateKeyPEM: String
    public let keyTag: String?

    public init(certificatePEM: String, privateKeyPEM: String, keyTag: String? = nil) {
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
        self.keyTag = keyTag
    }
}

public protocol ShadowClientPairingIdentityProviding {
    func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial
}

enum ShadowClientPairingIdentityDefaultsKeys {
    static let certificatePEM = "pairing.identity.certificatePEM"
    static let privateKeyPEM = "pairing.identity.privateKeyPEM"
    static let keyTag = "pairing.identity.keyTag"
    static let uniqueID = "pairing.identity.uniqueId"
}

public struct ShadowClientUserDefaultsIdentityProvider: ShadowClientPairingIdentityProviding {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial {
        guard
            let certificatePEM = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM),
            let privateKeyPEM = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM),
            !certificatePEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return ShadowClientPairingIdentityMaterial(
            certificatePEM: certificatePEM,
            privateKeyPEM: privateKeyPEM,
            keyTag: defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.keyTag)
        )
    }
}

public protocol ShadowClientGameStreamControlClient: Sendable {
    func pair(
        host: String,
        pin: String,
        appVersion: String?,
        httpsPort: Int?
    ) async throws -> ShadowClientGameStreamPairingResult
    func getClipboard(
        host: String,
        httpsPort: Int
    ) async throws -> String
    func setClipboard(
        host: String,
        httpsPort: Int,
        text: String
    ) async throws
    func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        forceLaunch: Bool,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult
    func cancelActiveSession(
        host: String,
        httpsPort: Int
    ) async throws
}

public extension ShadowClientGameStreamControlClient {
    func getClipboard(
        host: String,
        httpsPort: Int
    ) async throws -> String {
        _ = host
        _ = httpsPort
        throw ShadowClientGameStreamError.requestFailed("Clipboard sync is unsupported.")
    }

    func setClipboard(
        host: String,
        httpsPort: Int,
        text: String
    ) async throws {
        _ = host
        _ = httpsPort
        _ = text
        throw ShadowClientGameStreamError.requestFailed("Clipboard sync is unsupported.")
    }

    func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        try await launch(
            host: host,
            httpsPort: httpsPort,
            appID: appID,
            currentGameID: currentGameID,
            forceLaunch: false,
            settings: settings
        )
    }

    func cancelActiveSession(
        host: String,
        httpsPort: Int
    ) async throws {
        _ = host
        _ = httpsPort
    }
}

public enum ShadowClientGameStreamControlError: Error, Equatable, Sendable {
    case invalidPIN
    case invalidKeyMaterial
    case challengeRejected
    case pairingAlreadyInProgress
    case pinMismatch
    case mitmDetected
    case launchRejected
    case malformedResponse
}

extension ShadowClientGameStreamControlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPIN:
            return "PIN must be at least 4 characters."
        case .invalidKeyMaterial:
            return "Client key material is invalid."
        case .challengeRejected:
            return "Pairing challenge was rejected by host."
        case .pairingAlreadyInProgress:
            return "Host already has a pairing flow in progress."
        case .pinMismatch:
            return "Pairing PIN mismatch."
        case .mitmDetected:
            return "Server certificate signature verification failed."
        case .launchRejected:
            return "Host rejected launch request."
        case .malformedResponse:
            return "Host returned malformed response payload."
        }
    }
}

public actor ShadowClientPairingIdentityStore {
    public static let shared = ShadowClientPairingIdentityStore(
        provider: ShadowClientUserDefaultsIdentityProvider()
    )

    private let defaults: UserDefaults
    private let provider: any ShadowClientPairingIdentityProviding
    private var cachedUniqueID: String?
    private var cachedMaterial: ShadowClientPairingIdentityMaterial?

    public init(
        provider: any ShadowClientPairingIdentityProviding,
        defaults: UserDefaults = .standard
    ) {
        self.provider = provider
        self.defaults = defaults
    }

    public init(
        provider: any ShadowClientPairingIdentityProviding,
        defaultsSuiteName: String
    ) {
        let suiteDefaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.provider = provider
        self.defaults = suiteDefaults
    }

    public init(defaultsSuiteName: String) {
        let suiteDefaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.provider = ShadowClientUserDefaultsIdentityProvider(defaults: suiteDefaults)
        self.defaults = suiteDefaults
    }

    public func uniqueID() -> String {
        if let cachedUniqueID {
            return cachedUniqueID
        }

        if let stored = defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.uniqueID), !stored.isEmpty {
            cachedUniqueID = stored
            return stored
        }

        var randomValue: UInt64 = 0
        let status = withUnsafeMutableBytes(of: &randomValue) { buffer in
            SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
        }

        let generated: String
        if status == errSecSuccess {
            generated = String(randomValue, radix: 16)
        } else {
            generated = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }

        defaults.set(generated, forKey: ShadowClientPairingIdentityDefaultsKeys.uniqueID)
        cachedUniqueID = generated
        return generated
    }

    public func clientCertificatePEMData() throws -> Data {
        let material = try resolveMaterial()
        return Data(material.certificatePEM.utf8)
    }

    public func upsertIdentityMaterial(_ material: ShadowClientPairingIdentityMaterial) {
        cachedMaterial = material
        defaults.set(material.certificatePEM, forKey: ShadowClientPairingIdentityDefaultsKeys.certificatePEM)
        defaults.set(material.privateKeyPEM, forKey: ShadowClientPairingIdentityDefaultsKeys.privateKeyPEM)
        if let keyTag = material.keyTag {
            defaults.set(keyTag, forKey: ShadowClientPairingIdentityDefaultsKeys.keyTag)
        } else {
            defaults.removeObject(forKey: ShadowClientPairingIdentityDefaultsKeys.keyTag)
        }
    }

    public func clientCertificateSignature() throws -> Data {
        try withRecoveredMaterial { material in
            let certDER = try pemBodyData(pem: material.certificatePEM)
            return try ShadowClientX509DER.signatureBytes(fromCertificateDER: certDER)
        }
    }

    public func sign(_ message: Data) throws -> Data {
        try withRecoveredMaterial { material in
            try sign(message, material: material)
        }
    }

    public func tlsClientCertificateCredential() throws -> URLCredential {
        try withRecoveredMaterial { material in
            try makeTLSClientCertificateCredential(material: material)
        }
    }

    public func tlsClientCertificates() throws -> [SecCertificate] {
        try withRecoveredMaterial { material in
            [try makeTLSClientCertificate(material: material)]
        }
    }

    public func tlsClientIdentity() throws -> SecIdentity {
        try withRecoveredMaterial { material in
            try makeTLSClientIdentity(material: material)
        }
    }

    private func resolveMaterial() throws -> ShadowClientPairingIdentityMaterial {
        if let cachedMaterial {
            return cachedMaterial
        }

        do {
            let loaded = try provider.loadIdentityMaterial()
            let validated = try validateIdentityMaterial(loaded)
            cachedMaterial = validated
            return validated
        } catch {
            let generated = try ShadowClientPairingIdentityMaterialFactory.generate()
            upsertIdentityMaterial(generated)
            return generated
        }
    }

    private func withRecoveredMaterial<T>(
        operation: (ShadowClientPairingIdentityMaterial) throws -> T
    ) throws -> T {
        do {
            let material = try resolveMaterial()
            return try operation(material)
        } catch let error as ShadowClientGameStreamControlError {
            switch error {
            case .invalidKeyMaterial:
                let regenerated = try regenerateIdentityMaterial()
                return try operation(regenerated)
            case .invalidPIN, .pairingAlreadyInProgress, .challengeRejected, .pinMismatch, .mitmDetected, .launchRejected, .malformedResponse:
                throw error
            }
        } catch {
            throw error
        }
    }

    private func regenerateIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial {
        let generated = try ShadowClientPairingIdentityMaterialFactory.generate()
        upsertIdentityMaterial(generated)
        return generated
    }

    private func pemBodyData(pem: String) throws -> Data {
        let lines = pem
            .components(separatedBy: .newlines)
            .filter { line in
                !line.hasPrefix("-----BEGIN") &&
                    !line.hasPrefix("-----END") &&
                    !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .joined()

        guard let data = Data(base64Encoded: lines) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return data
    }

    private func validateIdentityMaterial(
        _ material: ShadowClientPairingIdentityMaterial
    ) throws -> ShadowClientPairingIdentityMaterial {
        let certDER = try pemBodyData(pem: material.certificatePEM)
        guard let cert = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }
        _ = try ShadowClientX509DER.signatureBytes(fromCertificateDER: certDER)

        let keyDER = try pemBodyData(pem: material.privateKeyPEM)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(keyDER as CFData, attributes as CFDictionary, &error) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard let certificatePublicKey = SecCertificateCopyKey(cert) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard SecKeyIsAlgorithmSupported(certificatePublicKey, .verify, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        let probe = Data("shadow-client-material-validation".utf8)
        guard let probeSignature = SecKeyCreateSignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            probe as CFData,
            &error
        ) as Data? else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        var verifyError: Unmanaged<CFError>?
        guard SecKeyVerifySignature(
            certificatePublicKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            probe as CFData,
            probeSignature as CFData,
            &verifyError
        ) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return material
    }

    private func sign(
        _ message: Data,
        material: ShadowClientPairingIdentityMaterial
    ) throws -> Data {
        let keyData = try pemBodyData(pem: material.privateKeyPEM)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard SecKeyIsAlgorithmSupported(privateKey, .sign, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            &error
        ) as Data? else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return signature
    }

    private func makeTLSClientCertificateCredential(
        material: ShadowClientPairingIdentityMaterial
    ) throws -> URLCredential {
        let certificate = try makeTLSClientCertificate(material: material)
        let identity = try makeTLSClientIdentity(material: material)

        return URLCredential(
            identity: identity,
            certificates: [certificate],
            persistence: .forSession
        )
    }

    private func makeTLSClientIdentity(
        material: ShadowClientPairingIdentityMaterial
    ) throws -> SecIdentity {
        let certificate = try makeTLSClientCertificate(material: material)
        let privateKey = try makeTLSClientPrivateKey(material: material)

        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }
        return identity
    }

    private func makeTLSClientCertificate(
        material: ShadowClientPairingIdentityMaterial
    ) throws -> SecCertificate {
        let certDER = try pemBodyData(pem: material.certificatePEM)
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }
        return certificate
    }

    private func makeTLSClientPrivateKey(
        material: ShadowClientPairingIdentityMaterial
    ) throws -> SecKey {
        let keyData = try pemBodyData(pem: material.privateKeyPEM)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }
        return privateKey
    }
}

public actor ShadowClientPinnedHostCertificateStore {
    public static let shared = ShadowClientPinnedHostCertificateStore()

    private enum DefaultsKeys {
        static let pinnedCertificates = "pairing.pinned.serverCertificates"
    }

    private let defaults: UserDefaults
    private var cached: [String: String]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cached = defaults.dictionary(forKey: DefaultsKeys.pinnedCertificates) as? [String: String] ?? [:]
    }

    public init(defaultsSuiteName: String) {
        let suiteDefaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.defaults = suiteDefaults
        self.cached = suiteDefaults.dictionary(forKey: DefaultsKeys.pinnedCertificates) as? [String: String] ?? [:]
    }

    public func certificateDER(forHost host: String) -> Data? {
        let key = normalizedHost(host)
        guard let value = cached[key] else {
            return nil
        }
        return Data(base64Encoded: value)
    }

    public func setCertificateDER(_ der: Data, forHost host: String) {
        let key = normalizedHost(host)
        cached[key] = der.base64EncodedString()
        defaults.set(cached, forKey: DefaultsKeys.pinnedCertificates)
    }

    public func removeCertificate(forHost host: String) {
        let key = normalizedHost(host)
        cached.removeValue(forKey: key)
        defaults.set(cached, forKey: DefaultsKeys.pinnedCertificates)
    }

    private func normalizedHost(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public actor NativeGameStreamControlClient: ShadowClientGameStreamControlClient {
    private static let pairingLogger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "Pairing"
    )
    private static let launchLogger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "Launch"
    )
    private static let videoCodecSupport = ShadowClientVideoCodecSupport()

    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let defaultHTTPPort: Int
    private let defaultHTTPSPort: Int
    private let defaultRequestTimeout: TimeInterval
    private let pairingPINEntryTimeout: TimeInterval
    private let pairingStageTimeout: TimeInterval

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
        defaultRequestTimeout: TimeInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout,
        pairingPINEntryTimeout: TimeInterval = ShadowClientGameStreamNetworkDefaults.pairingPINEntryTimeout,
        pairingStageTimeout: TimeInterval = ShadowClientGameStreamNetworkDefaults.pairingStageTimeout
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultHTTPSPort = defaultHTTPSPort
        self.defaultRequestTimeout = defaultRequestTimeout
        self.pairingPINEntryTimeout = pairingPINEntryTimeout
        self.pairingStageTimeout = pairingStageTimeout
    }

    public func pair(
        host: String,
        pin: String,
        appVersion: String?,
        httpsPort: Int?
    ) async throws -> ShadowClientGameStreamPairingResult {
        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPIN.count >= 4 else {
            throw ShadowClientGameStreamControlError.invalidPIN
        }

        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let httpsEndpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPSPort)
        let uniqueID = await identityStore.uniqueID()
        // Build TLS credential first so any material recovery happens before stage1 uploads client cert.
        let tlsClientCredential = try await identityStore.tlsClientCertificateCredential()
        let tlsClientCertificates = try await identityStore.tlsClientCertificates()
        let tlsClientIdentity = try await identityStore.tlsClientIdentity()
        let certPEMData = try await identityStore.clientCertificatePEMData()
        let clientCertSignature = try await identityStore.clientCertificateSignature()

        let hashAlgorithm = PairHashAlgorithm.from(appVersion: appVersion)
        let salt = Self.randomBytes(length: 16)
        let saltedPin = Data(salt + Data(trimmedPIN.utf8))
        let aesKey = Data(hashAlgorithm.digest(saltedPin).prefix(16))
        let stage1Parameters: [String: String] = [
            "devicename": "shadow-client",
            "updateState": "1",
            "phrase": "getservercert",
            "salt": salt.hexString,
            "clientcert": certPEMData.hexString,
        ]

        let stage1XML = try await requestPairXML(
            stage: "getservercert",
            host: endpoint.host,
            port: endpoint.port,
            scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
            parameters: stage1Parameters,
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingPINEntryTimeout
        )

        let stage1Doc = try parsePairStageXML(stage1XML, stage: "getservercert")
        guard stage1Doc.values["paired"]?.first == "1" else {
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        guard let plainCertHex = stage1Doc.values["plaincert"]?.first else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.pairingAlreadyInProgress
        }
        let serverCertDER: Data
        do {
            serverCertDER = try ShadowClientCertificateDERDecoder.decode(fromPlainCertHex: plainCertHex)
        } catch {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw error
        }

        let randomChallenge = Self.randomBytes(length: 16)
        let encryptedChallenge = try Self.cryptAES(
            input: randomChallenge,
            key: aesKey,
            operation: CCOperation(kCCEncrypt)
        )

        let stage2XML = try await requestPairXML(
            stage: "clientchallenge",
            host: endpoint.host,
            port: endpoint.port,
            scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "clientchallenge": encryptedChallenge.hexString,
            ],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
        let stage2Doc = try parsePairStageXML(stage2XML, stage: "clientchallenge")
        guard stage2Doc.values["paired"]?.first == "1" else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        guard
            let challengeResponseHex = stage2Doc.values["challengeresponse"]?.first,
            let challengeResponseCipher = Data(hexString: challengeResponseHex)
        else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.malformedResponse
        }

        let challengeResponseData = try Self.cryptAES(
            input: challengeResponseCipher,
            key: aesKey,
            operation: CCOperation(kCCDecrypt)
        )
        guard challengeResponseData.count >= hashAlgorithm.digestLength + 16 else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.malformedResponse
        }

        let serverResponse = Data(challengeResponseData.prefix(hashAlgorithm.digestLength))
        let challengeNonce = Data(challengeResponseData.dropFirst(hashAlgorithm.digestLength).prefix(16))
        let clientSecret = Self.randomBytes(length: 16)

        var challengeResponsePayload = Data()
        challengeResponsePayload.append(challengeNonce)
        challengeResponsePayload.append(clientCertSignature)
        challengeResponsePayload.append(clientSecret)

        var paddedHash = hashAlgorithm.digest(challengeResponsePayload)
        if paddedHash.count < 32 {
            paddedHash.append(Data(repeating: 0, count: 32 - paddedHash.count))
        }

        let encryptedResponseHash = try Self.cryptAES(
            input: paddedHash,
            key: aesKey,
            operation: CCOperation(kCCEncrypt)
        )

        let stage3XML = try await requestPairXML(
            stage: "serverchallengeresp",
            host: endpoint.host,
            port: endpoint.port,
            scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "serverchallengeresp": encryptedResponseHash.hexString,
            ],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
        let stage3Doc = try parsePairStageXML(stage3XML, stage: "serverchallengeresp")
        guard stage3Doc.values["paired"]?.first == "1" else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        guard
            let pairingSecretHex = stage3Doc.values["pairingsecret"]?.first,
            let pairingSecret = Data(hexString: pairingSecretHex),
            pairingSecret.count > 16
        else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.malformedResponse
        }

        let serverSecret = Data(pairingSecret.prefix(16))
        let serverSignature = Data(pairingSecret.dropFirst(16))

        let signatureValid = try Self.verifySignature(
            message: serverSecret,
            signature: serverSignature,
            certificateDER: serverCertDER
        )
        guard signatureValid else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.mitmDetected
        }

        let serverCertSignature = try ShadowClientX509DER.signatureBytes(fromCertificateDER: serverCertDER)
        var expectedResponseData = Data()
        expectedResponseData.append(randomChallenge)
        expectedResponseData.append(serverCertSignature)
        expectedResponseData.append(serverSecret)

        if hashAlgorithm.digest(expectedResponseData) != serverResponse {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.pinMismatch
        }

        let clientSecretSignature = try await identityStore.sign(clientSecret)
        var clientPairingSecret = Data()
        clientPairingSecret.append(clientSecret)
        clientPairingSecret.append(clientSecretSignature)

        let stage4XML = try await requestPairXML(
            stage: "clientpairingsecret",
            host: endpoint.host,
            port: endpoint.port,
            scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "clientpairingsecret": clientPairingSecret.hexString,
            ],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
        let stage4Doc = try parsePairStageXML(stage4XML, stage: "clientpairingsecret")
        guard stage4Doc.values["paired"]?.first == "1" else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        let resolvedHTTPSPort = httpsPort ?? httpsEndpoint.port
        let stage5Parameters: [String: String] = [
            "devicename": "shadow-client",
            "updateState": "1",
            "phrase": "pairchallenge",
        ]
        do {
            let stage5XML = try await requestPairXML(
                stage: "pairchallenge",
                host: endpoint.host,
                port: resolvedHTTPSPort,
                scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
                parameters: stage5Parameters,
                uniqueID: uniqueID,
                pinnedServerCertificateDER: Self.pairChallengePinnedServerCertificateDER(
                    serverCertificateDER: serverCertDER
                ),
                clientCertificateCredential: tlsClientCredential,
                clientCertificates: tlsClientCertificates,
                clientCertificateIdentity: tlsClientIdentity,
                timeout: pairingStageTimeout
            )
            let stage5Doc = try parsePairStageXML(stage5XML, stage: "pairchallenge")
            if stage5Doc.values["paired"]?.first != "1" {
                Self.pairingLogger.error(
                    "Pair stage pairchallenge rejected after successful clientpairingsecret; keeping pair result because Apollo already marked the client paired"
                )
            }
        } catch let error as ShadowClientGameStreamError {
            if Self.isNonFatalPairChallengeTransportFailure(error) {
                Self.pairingLogger.notice(
                    "Pair stage pairchallenge hit non-fatal HTTPS client-auth verification failure after clientpairingsecret; treating host as paired"
                )
            } else {
                try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
                throw error
            }
        } catch {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw error
        }

        await pinnedCertificateStore.setCertificateDER(serverCertDER, forHost: endpoint.host)
        return ShadowClientGameStreamPairingResult(host: endpoint.host)
    }

    static func pairChallengePinnedServerCertificateDER(serverCertificateDER: Data) -> Data? {
        _ = serverCertificateDER
        // Pairing no longer requires a prior certificate pin. We still persist the leaf after a
        // successful pair so post-pair HTTPS requests can use TOFU-based pinning.
        return nil
    }

    public func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        forceLaunch: Bool = false,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let uniqueID = await identityStore.uniqueID()
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(forHost: endpoint.host)
        let tlsClientCredential = try? await identityStore.tlsClientCertificateCredential()
        let tlsClientCertificates = try? await identityStore.tlsClientCertificates()
        let tlsClientIdentity = try? await identityStore.tlsClientIdentity()

        let remoteInputKey = Self.randomBytes(length: 16)
        let remoteInputIV = Self.randomBytes(length: 16)
        let keyID = remoteInputIV.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }

        let isSurround = settings.enableSurroundAudio && !settings.lowLatencyMode
        let surroundAudioInfo = isSurround ? 393_279 : 131_075
        let localAudioPlayMode = settings.playAudioOnHost ? "1" : "0"
        var parameters = Self.makeLaunchParameters(
            appID: appID,
            settings: settings,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: keyID,
            surroundAudioInfo: surroundAudioInfo,
            localAudioPlayMode: localAudioPlayMode
        )

        let resolvedCodecPreference = Self.resolvedLaunchCodecPreference(
            from: settings.preferredCodec,
            enableHDR: settings.enableHDR,
            enableYUV444: settings.enableYUV444
        )
        let verb = Self.resolvedLaunchVerb(
            appID: appID,
            currentGameID: currentGameID,
            forceLaunch: forceLaunch,
            preferredCodec: settings.preferredCodec,
            resolvedCodecPreference: resolvedCodecPreference
        )
        Self.launchLogger.notice(
            "Launch decision verb=\(verb.rawValue, privacy: .public), appID=\(appID, privacy: .public), currentGameID=\(currentGameID, privacy: .public), forceLaunch=\(forceLaunch, privacy: .public), preferredCodec=\(settings.preferredCodec.rawValue, privacy: .public), resolvedCodec=\(resolvedCodecPreference.rawValue, privacy: .public)"
        )
        if let codec = resolvedCodecPreference.launchParameterValue {
            // Apollo/GameStream stacks don't fully agree on this key, so send both.
            parameters["videoCodec"] = codec
            parameters["codec"] = codec
        }

        if settings.enableYUV444 {
            parameters["yuv444"] = "1"
        }
        if settings.unlockBitrateLimit {
            parameters["unlockBitrate"] = "1"
        }
        if settings.enableVSync {
            parameters["vsync"] = "1"
        }
        if settings.enableFramePacing {
            parameters["framePacing"] = "1"
        }
        if !settings.forceHardwareDecoding {
            parameters["forceHardwareDecode"] = "0"
        }
        if settings.optimizeGameSettingsForStreaming {
            parameters["optimizeGameSettings"] = "1"
        }
        if settings.quitAppOnHostAfterStreamEnds {
            parameters["quitappafter"] = "1"
        }

        if settings.enableHDR {
            parameters["hdrMode"] = "1"
            parameters["clientHdrCapVersion"] = "0"
            parameters["clientHdrCapSupportedFlagsInUint32"] = "0"
            parameters["clientHdrCapMetaDataId"] = "NV_STATIC_METADATA_TYPE_1"
            parameters["clientHdrCapDisplayData"] = ShadowClientGameStreamLaunchDefaults.hdrCapabilityPlaceholder
        }

        func requestControlXML(
            command: ShadowClientGameStreamCommand,
            parameters: [String: String]
        ) async throws -> String {
            try await ShadowClientGameStreamHTTPTransport.requestXML(
                host: endpoint.host,
                port: httpsPort,
                scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
                command: command.rawValue,
                parameters: parameters,
                uniqueID: uniqueID,
                pinnedServerCertificateDER: pinnedServerCertificate,
                clientCertificateCredential: tlsClientCredential,
                clientCertificates: tlsClientCertificates,
                clientCertificateIdentity: tlsClientIdentity,
                timeout: defaultRequestTimeout
            )
        }

        let requiresFreshLaunch = verb == .launch && currentGameID > 0
        if requiresFreshLaunch {
            do {
                _ = try await requestControlXML(command: .cancel, parameters: [:])
                Self.launchLogger.notice(
                    "Issued cancel before launch to reset active session currentGameID=\(currentGameID, privacy: .public)"
                )
            } catch {
                Self.launchLogger.error(
                    "Cancel before launch failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        do {
            let launchXML = try await requestControlXML(
                command: verb,
                parameters: parameters
            )
            return try Self.parseLaunchResult(
                launchXML: launchXML,
                command: verb,
                remoteInputKey: remoteInputKey,
                remoteInputKeyID: keyID
            )
        } catch {
            if verb == .resume {
                Self.launchLogger.notice(
                    "Resume failed; retrying launch after cancel. reason=\(error.localizedDescription, privacy: .public)"
                )
                do {
                    _ = try await requestControlXML(command: .cancel, parameters: [:])
                } catch {
                    Self.launchLogger.error(
                        "Cancel before resume fallback launch failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                do {
                    let launchXML = try await requestControlXML(
                        command: .launch,
                        parameters: parameters
                    )
                    return try Self.parseLaunchResult(
                        launchXML: launchXML,
                        command: .launch,
                        remoteInputKey: remoteInputKey,
                        remoteInputKeyID: keyID
                    )
                } catch {
                    throw Self.remapLaunchError(error)
                }
            }
            if requiresFreshLaunch,
               Self.isAppAlreadyRunningResponse(error)
            {
                Self.launchLogger.notice(
                    "Launch reported running app; retrying once after cancel"
                )
                do {
                    _ = try await requestControlXML(command: .cancel, parameters: [:])
                } catch {
                    Self.launchLogger.error(
                        "Retry cancel failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
                do {
                    let launchXML = try await requestControlXML(
                        command: verb,
                        parameters: parameters
                    )
                    return try Self.parseLaunchResult(
                        launchXML: launchXML,
                        command: verb,
                        remoteInputKey: remoteInputKey,
                        remoteInputKeyID: keyID
                    )
                } catch {
                    throw Self.remapLaunchError(error)
                }
            }
            throw Self.remapLaunchError(error)
        }
    }

    public func cancelActiveSession(
        host: String,
        httpsPort: Int
    ) async throws {
        let uniqueID = await identityStore.uniqueID()
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(forHost: host)
        let tlsClientCredential = try? await identityStore.tlsClientCertificateCredential()
        let tlsClientCertificates = try? await identityStore.tlsClientCertificates()
        let tlsClientIdentity = try? await identityStore.tlsClientIdentity()

        _ = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: host,
            port: httpsPort,
            scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
            command: ShadowClientGameStreamCommand.cancel.rawValue,
            parameters: [:],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: pinnedServerCertificate,
            clientCertificateCredential: tlsClientCredential,
            clientCertificates: tlsClientCertificates,
            clientCertificateIdentity: tlsClientIdentity,
            timeout: defaultRequestTimeout
        )
    }

    static func makeLaunchParameters(
        appID: Int,
        settings: ShadowClientGameStreamLaunchSettings,
        remoteInputKey: Data,
        remoteInputKeyID: UInt32,
        surroundAudioInfo: Int,
        localAudioPlayMode: String
    ) -> [String: String] {
        var parameters: [String: String] = [
            "appid": "\(appID)",
            "mode": "\(settings.width)x\(settings.height)x\(settings.fps)",
            "additionalStates": "1",
            "sops": "1",
            "rikey": remoteInputKey.hexString,
            "rikeyid": "\(remoteInputKeyID)",
            "localAudioPlayMode": localAudioPlayMode,
            "surroundAudioInfo": "\(surroundAudioInfo)",
            "remoteControllersBitmap": "1",
            "gcmap": "1",
            "gcpersist": "0",
            "bitrate": "\(settings.bitrateKbps)",
        ]

        if settings.preferVirtualDisplay {
            parameters["virtualDisplay"] = "1"
        }
        if settings.resolutionScalePercent != 100 {
            parameters["scaleFactor"] = "\(settings.resolutionScalePercent)"
        }

        return parameters
    }

    public func setClipboard(
        host: String,
        httpsPort: Int,
        text: String
    ) async throws {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(forHost: endpoint.host)
        let tlsClientCertificates = try await identityStore.tlsClientCertificates()
        let tlsClientIdentity = try await identityStore.tlsClientIdentity()

        guard pinnedServerCertificate != nil else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host requires pairing before clipboard actions."
            )
        }

        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = endpoint.host
        components.port = httpsPort
        components.path = "/actions/clipboard"
        components.queryItems = [
            .init(name: "type", value: "text"),
            .init(name: "uuid", value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
        ]
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        let requestData = ShadowClientGameStreamHTTPTransport.makeHTTPRequestData(
            url: url,
            host: endpoint.host,
            method: "POST",
            headers: [
                "Content-Type": "text/plain; charset=utf-8",
            ],
            body: Data(text.utf8)
        )

        do {
            _ = try await ShadowClientGameStreamHTTPTransport.requestPinnedHTTPSData(
                url: url,
                requestData: requestData,
                pinnedServerCertificateDER: pinnedServerCertificate,
                clientCertificates: tlsClientCertificates,
                clientCertificateIdentity: tlsClientIdentity,
                timeout: defaultRequestTimeout
            )
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(error)
        }
    }

    public func getClipboard(
        host: String,
        httpsPort: Int
    ) async throws -> String {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(forHost: endpoint.host)
        let tlsClientCertificates = try await identityStore.tlsClientCertificates()
        let tlsClientIdentity = try await identityStore.tlsClientIdentity()

        guard pinnedServerCertificate != nil else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host requires pairing before clipboard actions."
            )
        }

        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = endpoint.host
        components.port = httpsPort
        components.path = "/actions/clipboard"
        components.queryItems = [
            .init(name: "type", value: "text"),
        ]
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        let requestData = ShadowClientGameStreamHTTPTransport.makeHTTPRequestData(
            url: url,
            host: endpoint.host,
            method: "GET"
        )

        do {
            let data = try await ShadowClientGameStreamHTTPTransport.requestPinnedHTTPSData(
                url: url,
                requestData: requestData,
                pinnedServerCertificateDER: pinnedServerCertificate,
                clientCertificates: tlsClientCertificates,
                clientCertificateIdentity: tlsClientIdentity,
                timeout: defaultRequestTimeout
            )
            guard let text = String(data: data, encoding: .utf8) else {
                throw ShadowClientGameStreamError.invalidResponse
            }
            return text
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(error)
        }
    }

    private static func resolvedLaunchVerb(
        appID: Int,
        currentGameID: Int,
        forceLaunch: Bool,
        preferredCodec: ShadowClientVideoCodecPreference,
        resolvedCodecPreference: ShadowClientVideoCodecPreference
    ) -> ShadowClientGameStreamCommand {
        if forceLaunch {
            return .launch
        }
        if currentGameID <= 0 {
            return .launch
        }
        if appID != currentGameID {
            return .launch
        }
        if didDowngradeCodecPreference(
            requested: preferredCodec,
            resolved: resolvedCodecPreference
        ) {
            return .launch
        }
        return .resume
    }

    private static func didDowngradeCodecPreference(
        requested: ShadowClientVideoCodecPreference,
        resolved: ShadowClientVideoCodecPreference
    ) -> Bool {
        switch requested {
        case .av1:
            return resolved != .av1
        case .auto:
            return resolved != .auto
        case .h265, .h264:
            return false
        }
    }

    private static func isAppAlreadyRunningResponse(_ error: Error) -> Bool {
        guard case let ShadowClientGameStreamError.responseRejected(code, message) = error else {
            return false
        }
        guard code == 400 else {
            return false
        }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("already running")
    }

    private static func remapLaunchError(_ error: Error) -> Error {
        if let streamError = error as? ShadowClientGameStreamError {
            return streamError
        }
        return ShadowClientGameStreamError.requestFailed(error.localizedDescription)
    }

    private static func parseLaunchResult(
        launchXML: String,
        command: ShadowClientGameStreamCommand,
        remoteInputKey: Data,
        remoteInputKeyID: UInt32
    ) throws -> ShadowClientGameStreamLaunchResult {
        let document = try ShadowClientXMLFlatDocumentParser.parse(xml: launchXML)
        try validateRootStatus(document.rootStatus)
        let sessionURL = document.values["sessionUrl0"]?.first
        return ShadowClientGameStreamLaunchResult(
            sessionURL: sessionURL,
            verb: command.rawValue,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: remoteInputKeyID
        )
    }

    private static func resolvedLaunchCodecPreference(
        from preferredCodec: ShadowClientVideoCodecPreference,
        enableHDR: Bool,
        enableYUV444: Bool
    ) -> ShadowClientVideoCodecPreference {
        videoCodecSupport.resolvePreferredCodec(
            preferredCodec,
            enableHDR: enableHDR,
            enableYUV444: enableYUV444
        )
    }

    private func parsePairResponseXML(_ xml: String) throws -> ShadowClientXMLFlatDocument {
        let document = try ShadowClientXMLFlatDocumentParser.parse(xml: xml)
        try Self.validateRootStatus(document.rootStatus)
        return document
    }

    private func parsePairStageXML(
        _ xml: String,
        stage: String
    ) throws -> ShadowClientXMLFlatDocument {
        do {
            return try parsePairResponseXML(xml)
        } catch let error as ShadowClientGameStreamError {
            throw Self.remapPairingStageError(error, stage: stage)
        }
    }

    private func requestPairXML(
        stage: String,
        host: String,
        port: Int,
        scheme: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential? = nil,
        clientCertificates: [SecCertificate]? = nil,
        clientCertificateIdentity: SecIdentity? = nil,
        timeout: TimeInterval
    ) async throws -> String {
        Self.pairingLogger.debug(
            "Pair stage \(stage, privacy: .public) start \(scheme, privacy: .public)://\(host, privacy: .public):\(port, privacy: .public)"
        )
        do {
            let xml = try await ShadowClientGameStreamHTTPTransport.requestXML(
                host: host,
                port: port,
                scheme: scheme,
                command: ShadowClientGameStreamCommand.pair.rawValue,
                parameters: parameters,
                uniqueID: uniqueID,
                pinnedServerCertificateDER: pinnedServerCertificateDER,
                clientCertificateCredential: clientCertificateCredential,
                clientCertificates: clientCertificates,
                clientCertificateIdentity: clientCertificateIdentity,
                timeout: timeout
            )
            Self.pairingLogger.debug(
                "Pair stage \(stage, privacy: .public) completed"
            )
            return xml
        } catch let error as ShadowClientGameStreamError {
            Self.pairingLogger.error(
                "Pair stage \(stage, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
            throw Self.remapPairingStageError(error, stage: stage)
        } catch {
            Self.pairingLogger.error(
                "Pair stage \(stage, privacy: .public) failed with non-stream error: \(error.localizedDescription, privacy: .public)"
            )
            throw ShadowClientGameStreamError.requestFailed(
                "Pairing \(stage) failed: \(error.localizedDescription)"
            )
        }
    }

    private func sendUnpair(host: String, port: Int, uniqueID: String) async throws {
        _ = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: host,
            port: port,
            scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
            command: ShadowClientGameStreamCommand.unpair.rawValue,
            parameters: [:],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
    }

    private static func parseHostEndpoint(host: String, fallbackPort: Int) throws -> (host: String, port: Int) {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
        guard let url = URL(string: candidate), let parsedHost = url.host else {
            throw ShadowClientGameStreamError.invalidHost
        }

        return (parsedHost, url.port ?? fallbackPort)
    }

    private static func validateRootStatus(_ root: ShadowClientXMLRootStatus?) throws {
        guard let root else {
            throw ShadowClientGameStreamError.malformedXML
        }

        if root.code == 200 {
            return
        }

        throw ShadowClientGameStreamError.responseRejected(code: root.code, message: root.message)
    }

    private static func randomBytes(length: Int) -> Data {
        guard length > 0 else {
            return Data()
        }

        var data = Data(count: length)
        _ = data.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(kSecRandomDefault, length, rawBuffer.baseAddress!)
        }
        return data
    }

    private static func cryptAES(
        input: Data,
        key: Data,
        operation: CCOperation
    ) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        var output = Data(count: input.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0

        let status = output.withUnsafeMutableBytes { outputBuffer in
            input.withUnsafeBytes { inputBuffer in
                key.withUnsafeBytes { keyBuffer in
                    CCCrypt(
                        operation,
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode),
                        keyBuffer.baseAddress,
                        key.count,
                        nil,
                        inputBuffer.baseAddress,
                        input.count,
                        outputBuffer.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private static func verifySignature(
        message: Data,
        signature: Data,
        certificateDER: Data
    ) throws -> Bool {
        guard let cert = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let key = SecCertificateCopyKey(cert)
        else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard SecKeyIsAlgorithmSupported(key, .verify, .rsaSignatureMessagePKCS1v15SHA256) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            key,
            .rsaSignatureMessagePKCS1v15SHA256,
            message as CFData,
            signature as CFData,
            &error
        )
    }

    private static func remapPairingStageError(
        _ error: ShadowClientGameStreamError,
        stage: String
    ) -> ShadowClientGameStreamError {
        switch error {
        case let .requestFailed(message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let timeoutLike = normalized.contains("timed out") || normalized.contains("timeout")
            guard timeoutLike, stage == "getservercert" else {
                let base = message.trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = base.isEmpty ? "Host request failed." : base
                return .requestFailed("Pairing \(stage) failed: \(detail)")
            }

            return .requestFailed(
                "Pairing timed out while waiting for Apollo PIN confirmation. Enter the displayed PIN on the host and retry."
            )
        case let .responseRejected(code, message):
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return .responseRejected(
                    code: code,
                    message: "Pairing \(stage) rejected by host."
                )
            }

            return .responseRejected(
                code: code,
                message: "Pairing \(stage) rejected by host: \(detail)"
            )
        case .invalidResponse:
            return .requestFailed("Pairing \(stage) failed: Host response is invalid.")
        case .malformedXML:
            return .requestFailed("Pairing \(stage) failed: Host returned malformed XML.")
        case .invalidHost, .invalidURL:
            return error
        }
    }

    static func isNonFatalPairChallengeTransportFailure(_ error: ShadowClientGameStreamError) -> Bool {
        guard case let .requestFailed(message) = error else {
            return false
        }

        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("certificate required")
    }
}

private enum PairHashAlgorithm {
    case sha1
    case sha256

    var digestLength: Int {
        switch self {
        case .sha1:
            return 20
        case .sha256:
            return 32
        }
    }

    func digest(_ data: Data) -> Data {
        switch self {
        case .sha1:
            return Data(Insecure.SHA1.hash(data: data))
        case .sha256:
            return Data(SHA256.hash(data: data))
        }
    }

    static func from(appVersion: String?) -> PairHashAlgorithm {
        guard
            let appVersion,
            let firstComponent = appVersion.split(separator: ".").first,
            let major = Int(firstComponent)
        else {
            return .sha256
        }

        return major >= 7 ? .sha256 : .sha1
    }
}

enum ShadowClientCertificateDERDecoder {
    static func decode(fromPlainCertHex plainCertHex: String) throws -> Data {
        guard let plainCertificateBytes = Data(hexString: plainCertHex), !plainCertificateBytes.isEmpty else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        if SecCertificateCreateWithData(nil, plainCertificateBytes as CFData) != nil {
            return plainCertificateBytes
        }

        guard
            let plainCertificateText = String(data: plainCertificateBytes, encoding: .utf8),
            let pemBodyDER = Data(pemEncodedCertificate: plainCertificateText),
            SecCertificateCreateWithData(nil, pemBodyDER as CFData) != nil
        else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return pemBodyDER
    }
}

enum ShadowClientGameStreamTLSFailure: Equatable, Sendable {
    case serverCertificateMismatch
    case clientCertificateRequired
}

enum ShadowClientGameStreamHTTPTransport {
    // Preserve the legacy protocol token expected by Apollo/GameStream endpoints.
    private static let shadowClientCompatibleUniqueID = "0123456789ABCDEF"
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "GameStreamHTTP"
    )

    static func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential? = nil,
        clientCertificates: [SecCertificate]? = nil,
        clientCertificateIdentity: SecIdentity? = nil,
        timeout: TimeInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
    ) async throws -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/\(command)"

        var queryItems: [URLQueryItem] = parameters
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let requestUUID = UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        queryItems.append(.init(name: "uniqueid", value: shadowClientCompatibleUniqueID))
        queryItems.append(.init(name: "uuid", value: requestUUID))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        let requestStageLabel = "\(scheme.uppercased()) \(command)"
        logger.notice(
            "GameStream request start stage=\(requestStageLabel, privacy: .public) host=\(host, privacy: .public) port=\(port, privacy: .public)"
        )

        do {
            let connectionTargets = resolvedConnectionTargets(for: host)
            let targetsSummary = connectionTargets.joined(separator: ",")
            logger.notice(
                "GameStream request targets stage=\(requestStageLabel, privacy: .public) host=\(host, privacy: .public) targets=\(targetsSummary, privacy: .public)"
            )
            if scheme == ShadowClientGameStreamNetworkDefaults.httpsScheme {
                return try await requestPinnedHTTPSXML(
                    url: url,
                    requestHost: host,
                    connectionTargets: connectionTargets,
                    pinnedServerCertificateDER: pinnedServerCertificateDER,
                    clientCertificates: clientCertificates,
                    clientCertificateIdentity: clientCertificateIdentity,
                    timeout: timeout
                )
            } else {
                return try await requestPlainHTTPXML(
                    url: url,
                    requestHost: host,
                    connectionTargets: connectionTargets,
                    timeout: timeout
                )
            }
        } catch {
            logger.error(
                "GameStream request failed stage=\(requestStageLabel, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            throw requestStageFailureError(
                error,
                stageLabel: requestStageLabel
            )
        }
    }

    static func requestFailureError(
        _ error: Error,
        tlsFailure: ShadowClientGameStreamTLSFailure? = nil
    ) -> ShadowClientGameStreamError {
        if let tlsFailure {
            switch tlsFailure {
            case .serverCertificateMismatch:
                return .responseRejected(code: 401, message: "Server certificate mismatch")
            case .clientCertificateRequired:
                return .requestFailed("TLSV1_ALERT_CERTIFICATE_REQUIRED: certificate required")
            }
        }

        return .requestFailed(requestFailureMessage(error))
    }

    private static func requestStageFailureError(
        _ error: Error,
        stageLabel: String
    ) -> ShadowClientGameStreamError {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return .requestFailed("\(stageLabel) timed out")
        }

        if let gameStreamError = error as? ShadowClientGameStreamError {
            switch gameStreamError {
            case let .requestFailed(message):
                let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized.contains("timed out") || normalized.contains("timeout") {
                    return .requestFailed("\(stageLabel) timed out: \(message)")
                }
                return gameStreamError
            default:
                return gameStreamError
            }
        }

        return requestFailureError(error)
    }

    private static func requestFailureMessage(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .appTransportSecurityRequiresSecureConnection {
            return "Insecure HTTP is blocked by App Transport Security for this request."
        }

        return error.localizedDescription
    }

    private static func requestPlainHTTPXML(
        url: URL,
        requestHost: String,
        connectionTargets: [String],
        timeout: TimeInterval
    ) async throws -> String {
        guard let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80))
        else {
            throw ShadowClientGameStreamError.invalidURL
        }

        var failures: [Error] = []
        let startedAt = ContinuousClock.now

        for connectionTarget in connectionTargets {
            let connection = NWConnection(
                host: .init(connectionTarget),
                port: port,
                using: .tcp
            )
            do {
                try await waitForReady(
                    connection,
                    timeout: remainingPerTargetTimeout(
                        startedAt: startedAt,
                        overallTimeout: timeout
                    )
                )
            } catch let urlError as URLError where urlError.code == .timedOut {
                logger.error(
                    "Plain HTTP connection ready timed out host=\(requestHost, privacy: .public) connect-host=\(connectionTarget, privacy: .public) port=\(port.rawValue, privacy: .public)"
                )
                failures.append(ShadowClientGameStreamError.requestFailed("connection ready timed out"))
                connection.cancel()
                continue
            } catch {
                failures.append(error)
                connection.cancel()
                continue
            }
            defer {
                connection.cancel()
            }

            let requestData = makePlainHTTPRequestData(url: url, host: requestHost)
            do {
                try await send(requestData, over: connection)
                let responseData = try await receiveHTTPResponse(
                    over: connection,
                    timeout: remainingPerTargetTimeout(
                        startedAt: startedAt,
                        overallTimeout: timeout
                    )
                )
                let body = try extractHTTPBody(from: responseData)
                guard let xml = String(data: body, encoding: .utf8), !xml.isEmpty else {
                    throw ShadowClientGameStreamError.malformedXML
                }
                return xml
            } catch let urlError as URLError where urlError.code == .timedOut {
                logger.error(
                    "Plain HTTP response receive timed out host=\(requestHost, privacy: .public) connect-host=\(connectionTarget, privacy: .public) port=\(port.rawValue, privacy: .public)"
                )
                failures.append(ShadowClientGameStreamError.requestFailed("response receive timed out"))
            } catch {
                failures.append(error)
            }
        }

        throw failures.last ?? ShadowClientGameStreamError.requestFailed("HTTP transport failed")
    }

    static func requestPinnedHTTPSData(
        url: URL,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> Data {
        guard let host = url.host else {
            throw ShadowClientGameStreamError.invalidURL
        }
        let startedAt = ContinuousClock.now
        var failures: [Error] = []

        for connectionTarget in resolvedConnectionTargets(for: host) {
            do {
                let connectURL = try urlByReplacingHost(url, with: connectionTarget)
                return try await ShadowClientSecureHTTPStreamTransport.requestData(
                    url: connectURL,
                    requestHost: host,
                    connectHost: connectionTarget,
                    requestData: requestData,
                    pinnedServerCertificateDER: pinnedServerCertificateDER,
                    clientCertificates: clientCertificates,
                    clientCertificateIdentity: clientCertificateIdentity,
                    timeout: remainingPerTargetTimeout(
                        startedAt: startedAt,
                        overallTimeout: timeout
                    )
                )
            } catch {
                failures.append(error)
            }
        }

        throw failures.last ?? ShadowClientGameStreamError.requestFailed("HTTPS transport failed")
    }

    private static func requestPinnedHTTPSXML(
        url: URL,
        requestHost: String,
        connectionTargets: [String],
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> String {
        guard url.host != nil else {
            throw ShadowClientGameStreamError.invalidURL
        }
        let startedAt = ContinuousClock.now
        var failures: [Error] = []
        let credential = clientCertificateCredential(
            identity: clientCertificateIdentity,
            certificates: clientCertificates
        )

        for connectionTarget in connectionTargets {
            do {
                let connectURL = try urlByReplacingHost(url, with: connectionTarget)
                return try await requestPinnedHTTPSXMLUsingURLSession(
                    url: connectURL,
                    requestHost: requestHost,
                    connectHost: connectionTarget,
                    pinnedServerCertificateDER: pinnedServerCertificateDER,
                    clientCertificateCredential: credential,
                    timeout: remainingPerTargetTimeout(
                        startedAt: startedAt,
                        overallTimeout: timeout
                    )
                )
            } catch {
                failures.append(error)
            }
        }

        throw failures.last ?? ShadowClientGameStreamError.requestFailed("HTTPS transport failed")
    }

    private static func requestPinnedHTTPSXMLUsingURLSession(
        url: URL,
        requestHost: String,
        connectHost: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?,
        timeout: TimeInterval
    ) async throws -> String {
        let delegate = ShadowClientServerTrustURLSessionDelegate(
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificateCredential: clientCertificateCredential
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )
        defer {
            session.invalidateAndCancel()
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue(
            "\(requestHost)\(url.port.map { ":\($0)" } ?? "")",
            forHTTPHeaderField: "Host"
        )
        request.setValue("close", forHTTPHeaderField: "Connection")

        do {
            let (data, response) = try await session.data(for: request, delegate: delegate)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ShadowClientGameStreamError.invalidResponse
            }
            guard (200 ..< 300).contains(httpResponse.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw ShadowClientGameStreamError.responseRejected(
                    code: httpResponse.statusCode,
                    message: message
                )
            }
            guard let xml = String(data: data, encoding: .utf8), !xml.isEmpty else {
                throw ShadowClientGameStreamError.malformedXML
            }
            return xml
        } catch {
            if let urlError = error as? URLError, urlError.code == .timedOut {
                logger.error(
                    "Secure HTTP timed out host=\(requestHost, privacy: .public) connect-host=\(connectHost, privacy: .public) stage=session data"
                )
            }
            throw requestFailureError(error, tlsFailure: delegate.tlsFailure)
        }
    }

    static func connectionTargetCandidates(
        for host: String,
        resolvedHosts: [String]
    ) -> [String] {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            return []
        }

        let shouldAllowLoopback = isLoopbackHost(normalizedHost)
        var seen: Set<String> = []
        var preferred: [String] = []
        var deferred: [String] = []

        for candidate in resolvedHosts {
            let trimmedCandidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedCandidate.isEmpty else {
                continue
            }
            let normalizedCandidate = trimmedCandidate.lowercased()
            guard seen.insert(normalizedCandidate).inserted else {
                continue
            }

            if isLoopbackHost(trimmedCandidate), !shouldAllowLoopback {
                continue
            }

            if isScopedLinkLocalIPv6Host(trimmedCandidate) {
                continue
            }

            if isLinkLocalIPv6Host(trimmedCandidate) {
                deferred.append(trimmedCandidate)
                continue
            }

            preferred.append(trimmedCandidate)
        }

        let candidates = preferred + deferred
        return candidates.isEmpty ? [normalizedHost] : candidates
    }

    private static func resolvedConnectionTargets(for host: String) -> [String] {
        connectionTargetCandidates(
            for: host,
            resolvedHosts: resolveNumericHosts(for: host)
        )
    }

    private static func resolveNumericHosts(for host: String) -> [String] {
        if parseIPv4Literal(host) != nil || parseIPv6Literal(host) != nil {
            return [host]
        }

        var results = resolveNumericHostsUsingGetAddrInfo(for: host)
        if results.isEmpty {
            results = resolveNumericHostsUsingCFHost(for: host)
        }
        return results.isEmpty ? [host] : results
    }

    private static func resolveNumericHostsUsingGetAddrInfo(for host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &resultPointer)
        guard status == 0, let resultPointer else {
            return []
        }
        defer {
            freeaddrinfo(resultPointer)
        }

        var results: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = resultPointer
        while let current = cursor {
            var hostnameBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                current.pointee.ai_addr,
                socklen_t(current.pointee.ai_addrlen),
                &hostnameBuffer,
                socklen_t(hostnameBuffer.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            if status == 0 {
                let numericHost = String(cString: hostnameBuffer)
                if !numericHost.isEmpty {
                    results.append(numericHost)
                }
            }
            cursor = current.pointee.ai_next
        }

        return results
    }

    private static func resolveNumericHostsUsingCFHost(for host: String) -> [String] {
        let cfHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
        var streamError = CFStreamError()
        guard CFHostStartInfoResolution(cfHost, .addresses, &streamError) else {
            return []
        }

        var hasBeenResolved = DarwinBoolean(false)
        guard let addressArray = CFHostGetAddressing(cfHost, &hasBeenResolved)?.takeUnretainedValue() as? [Data],
              hasBeenResolved.boolValue
        else {
            return []
        }

        var seen: Set<String> = []
        var results: [String] = []

        for addressData in addressArray {
            let hostString = addressData.withUnsafeBytes { rawBuffer -> String? in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return nil
                }
                let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
                let length = socklen_t(addressData.count)
                return numericHostString(
                    from: UnsafeMutablePointer(mutating: sockaddrPointer),
                    length: length
                )
            }

            guard let hostString else {
                continue
            }
            let normalized = hostString.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }
            results.append(hostString)
        }

        return results
    }

    private static func numericHostString(
        from address: UnsafeMutablePointer<sockaddr>,
        length: socklen_t
    ) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            length,
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func remainingPerTargetTimeout(
        startedAt: ContinuousClock.Instant,
        overallTimeout: TimeInterval
    ) -> TimeInterval {
        let elapsed = startedAt.duration(to: ContinuousClock.now)
        let elapsedSeconds = Double(elapsed.components.seconds) +
            (Double(elapsed.components.attoseconds) / 1_000_000_000_000_000_000)
        let remaining = overallTimeout - elapsedSeconds
        return max(0.75, min(1.5, remaining))
    }

    private static func urlByReplacingHost(_ url: URL, with host: String) throws -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ShadowClientGameStreamError.invalidURL
        }
        components.host = formattedURLHost(host)
        guard let updatedURL = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }
        return updatedURL
    }

    private static func formattedURLHost(_ host: String) -> String {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedHost.contains(":"), !trimmedHost.hasPrefix("["), !trimmedHost.hasSuffix("]") else {
            return trimmedHost
        }
        return "[\(trimmedHost)]"
    }

    static func urlForConnectionTarget(_ url: URL, host: String) throws -> URL {
        try urlByReplacingHost(url, with: host)
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost" || normalized == "::1" || normalized.hasPrefix("127.")
    }

    private static func isLinkLocalIPv6Host(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.hasPrefix("fe8") || normalized.hasPrefix("fe9") ||
            normalized.hasPrefix("fea") || normalized.hasPrefix("feb")
    }

    private static func isScopedLinkLocalIPv6Host(_ host: String) -> Bool {
        isLinkLocalIPv6Host(host) && host.contains("%")
    }

    private static func parseIPv4Literal(_ host: String) -> in_addr? {
        var parsed = in_addr()
        let result = host.withCString { cString in
            inet_pton(AF_INET, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }

    private static func parseIPv6Literal(_ host: String) -> in6_addr? {
        var parsed = in6_addr()
        let result = host.withCString { cString in
            inet_pton(AF_INET6, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }

    private static func clientCertificateCredential(
        identity: SecIdentity?,
        certificates: [SecCertificate]?
    ) -> URLCredential? {
        guard let identity else {
            return nil
        }

        var credentialCertificates: [Any] = [identity]
        if let certificates {
            credentialCertificates.append(contentsOf: certificates)
        }
        return URLCredential(
            identity: identity,
            certificates: credentialCertificates,
            persistence: .forSession
        )
    }

    static func makeHTTPRequestData(
        url: URL,
        host: String,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) -> Data {
        let path = (url.path.isEmpty ? "/" : url.path) + (url.query.map { "?\($0)" } ?? "")
        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(host)\(url.port.map { ":\($0)" } ?? "")",
            "Connection: close",
        ]
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                lines.append("\(key): \(value)")
            }
        }
        if let body {
            lines.append("Content-Length: \(body.count)")
        }
        lines.append("")
        lines.append("")
        var request = Data(lines.joined(separator: "\r\n").utf8)
        if let body {
            request.append(body)
        }
        return request
    }

    fileprivate static func makePlainHTTPRequestData(url: URL, host: String) -> Data {
        makeHTTPRequestData(url: url, host: host, method: "GET")
    }

    fileprivate static func extractHTTPBody(from responseData: Data) throws -> Data {
        guard let separatorRange = responseData.range(
            of: Data("\r\n\r\n".utf8)
        ) else {
            throw ShadowClientGameStreamError.invalidResponse
        }
        return responseData[separatorRange.upperBound...]
    }

    private static func waitForReady(
        _ connection: NWConnection,
        timeout: TimeInterval
    ) async throws {
        final class ResumeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var resumed = false

            func markIfNeeded() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return false }
                resumed = true
                return true
            }
        }

        let gate = ResumeGate()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let deadline = DispatchTime.now() + timeout

            @Sendable func resume(_ result: Result<Void, Error>) {
                guard gate.markIfNeeded() else { return }
                connection.stateUpdateHandler = nil
                continuation.resume(with: result)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    resume(.success(()))
                case let .failed(error):
                    resume(.failure(error))
                case .cancelled:
                    resume(.failure(ShadowClientGameStreamError.requestFailed("HTTP transport cancelled")))
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
                resume(.failure(URLError(.timedOut)))
            }
        }
    }

    private static func send(
        _ data: Data,
        over connection: NWConnection
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private static func receiveHTTPResponse(
        over connection: NWConnection,
        timeout: TimeInterval
    ) async throws -> Data {
        final class ResumeGate: @unchecked Sendable {
            private let lock = NSLock()
            private var resumed = false

            func markIfNeeded() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                guard !resumed else { return false }
                resumed = true
                return true
            }
        }

        let gate = ResumeGate()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let deadline = DispatchTime.now() + timeout
            var responseData = Data()

            @Sendable func resume(_ result: Result<Data, Error>) {
                guard gate.markIfNeeded() else { return }
                continuation.resume(with: result)
            }

            func receiveNext() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
                    if let error {
                        resume(.failure(error))
                        return
                    }

                    if let content, !content.isEmpty {
                        responseData.append(content)
                    }

                    if isComplete {
                        resume(.success(responseData))
                        return
                    }

                    receiveNext()
                }
            }

            receiveNext()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline) {
                resume(.failure(URLError(.timedOut)))
            }
        }
    }
}

private final class ShadowClientSecureHTTPStreamTransport: @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "GameStreamHTTPS"
    )
    private let requestHost: String
    private let connectHost: String
    private let url: URL
    private let pinnedServerCertificateDER: Data?
    private let clientCertificates: [SecCertificate]?
    private let clientCertificateIdentity: SecIdentity?
    private let timeout: TimeInterval
    private let requestData: Data
    private let queue = DispatchQueue(
        label: "com.skyline23.shadow-client.pairing.secure-http",
        qos: .userInitiated
    )

    private var readStream: CFReadStream?
    private var writeStream: CFWriteStream?
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var responseData = Data()
    private var expectedResponseBodyLength: Int?
    private var headerTerminatorUpperBound: Int?
    private var requestOffset = 0
    private var readOpen = false
    private var writeOpen = false
    private var peerValidated = false
    private var completed = false
    private var timeoutStage = "stream open"

    private init(
        url: URL,
        requestHost: String,
        connectHost: String,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) {
        self.url = url
        self.requestHost = requestHost
        self.connectHost = connectHost
        self.pinnedServerCertificateDER = pinnedServerCertificateDER
        self.clientCertificates = clientCertificates
        self.clientCertificateIdentity = clientCertificateIdentity
        self.timeout = timeout
        self.requestData = requestData
    }

    static func requestData(
        url: URL,
        requestHost: String,
        connectHost: String,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> Data {
        let transport = ShadowClientSecureHTTPStreamTransport(
            url: url,
            requestHost: requestHost,
            connectHost: connectHost,
            requestData: requestData,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity,
            timeout: timeout
        )
        return try await transport.start()
    }

    static func requestXML(
        url: URL,
        requestHost: String,
        connectHost: String,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> String {
        let responseData = try await ShadowClientSecureHTTPStreamTransport.requestData(
            url: url,
            requestHost: requestHost,
            connectHost: connectHost,
            requestData: requestData,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity,
            timeout: timeout
        )
        guard let xml = String(data: responseData, encoding: .utf8), !xml.isEmpty else {
            throw ShadowClientGameStreamError.malformedXML
        }
        return xml
    }

    private func start() async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            queue.async {
                self.continuation = continuation
                do {
                    try self.openStreams()
                } catch {
                    self.finish(.failure(error))
                }
            }
        }
    }

    private func openStreams() throws {
        var readRef: Unmanaged<CFReadStream>?
        var writeRef: Unmanaged<CFWriteStream>?
        CFStreamCreatePairWithSocketToHost(
            nil,
            connectHost as CFString,
            UInt32(url.port ?? 443),
            &readRef,
            &writeRef
        )

        guard let readStream = readRef?.takeRetainedValue(),
              let writeStream = writeRef?.takeRetainedValue()
        else {
            throw ShadowClientGameStreamError.invalidURL
        }

        self.readStream = readStream
        self.writeStream = writeStream

        let sslSettings = makeSSLSettings()
        let sslSettingsKey = unsafeBitCast(kCFStreamPropertySSLSettings, to: CFStreamPropertyKey.self)
        guard CFReadStreamSetProperty(readStream, sslSettingsKey, sslSettings),
              CFWriteStreamSetProperty(writeStream, sslSettingsKey, sslSettings)
        else {
            throw ShadowClientGameStreamError.requestFailed("Unable to configure HTTPS client identity")
        }

        var readContext = CFStreamClientContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: Self.streamContextRetain,
            release: Self.streamContextRelease,
            copyDescription: nil
        )
        var writeContext = CFStreamClientContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: Self.streamContextRetain,
            release: Self.streamContextRelease,
            copyDescription: nil
        )

        let readEvents = CFOptionFlags(
            CFStreamEventType.openCompleted.rawValue |
            CFStreamEventType.hasBytesAvailable.rawValue |
            CFStreamEventType.errorOccurred.rawValue |
            CFStreamEventType.endEncountered.rawValue
        )
        let writeEvents = CFOptionFlags(
            CFStreamEventType.openCompleted.rawValue |
            CFStreamEventType.canAcceptBytes.rawValue |
            CFStreamEventType.errorOccurred.rawValue |
            CFStreamEventType.endEncountered.rawValue
        )

        guard CFReadStreamSetClient(readStream, readEvents, Self.readCallback, &readContext),
              CFWriteStreamSetClient(writeStream, writeEvents, Self.writeCallback, &writeContext)
        else {
            throw ShadowClientGameStreamError.requestFailed("Unable to install HTTPS stream callbacks")
        }

        CFReadStreamSetDispatchQueue(readStream, queue)
        CFWriteStreamSetDispatchQueue(writeStream, queue)

        guard CFReadStreamOpen(readStream), CFWriteStreamOpen(writeStream) else {
            throw streamError(from: readStream, fallback: writeStream)
        }

        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Self.logger.error(
                "Secure HTTP timed out host=\(self.requestHost, privacy: .public) connect-host=\(self.connectHost, privacy: .public) stage=\(self.timeoutStage, privacy: .public)"
            )
            self.finish(.failure(
                ShadowClientGameStreamError.requestFailed("HTTPS \(self.timeoutStage) timed out")
            ))
        }
        self.timeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)
    }

    private func makeSSLSettings() -> CFDictionary {
        var settings: [CFString: Any] = [
            kCFStreamSSLValidatesCertificateChain: kCFBooleanFalse as Any,
            kCFStreamSSLPeerName: kCFNull!,
            kCFStreamSSLIsServer: kCFBooleanFalse as Any,
            kCFStreamSSLLevel: kCFStreamSocketSecurityLevelNegotiatedSSL,
        ]

        if let clientCertificateIdentity {
            var sslCertificates: [Any] = [clientCertificateIdentity]
            if let clientCertificates {
                sslCertificates.append(contentsOf: clientCertificates)
            }
            settings[kCFStreamSSLCertificates] = sslCertificates as CFArray
        }

        return settings as CFDictionary
    }

    private func handleRead(event: CFStreamEventType) {
        guard !completed, let readStream else { return }

        switch event {
        case .openCompleted:
            readOpen = true
            validatePeerIfPossible()
        case .hasBytesAvailable:
            validatePeerIfPossible()
            readAvailableBytes()
            maybeCompleteResponse()
        case .endEncountered:
            completeIfPossible()
        case .errorOccurred:
            finish(.failure(streamError(from: readStream, fallback: writeStream)))
        default:
            break
        }
    }

    private func handleWrite(event: CFStreamEventType) {
        guard !completed, let writeStream else { return }

        switch event {
        case .openCompleted:
            writeOpen = true
            validatePeerIfPossible()
        case .canAcceptBytes:
            guard validatePeerIfPossible() else { return }
            timeoutStage = "request write"
            Self.logger.notice(
                "Secure HTTP writable host=\(self.requestHost, privacy: .public) connect-host=\(self.connectHost, privacy: .public) stage=\(self.timeoutStage, privacy: .public)"
            )
            writePendingBytes()
        case .endEncountered:
            completeIfPossible()
        case .errorOccurred:
            finish(.failure(streamError(from: readStream, fallback: writeStream)))
        default:
            break
        }
    }

    @discardableResult
    private func validatePeerIfPossible() -> Bool {
        guard !peerValidated else { return true }
        guard readOpen, writeOpen, let readStream else { return false }
        let peerTrustKey = unsafeBitCast(kCFStreamPropertySSLPeerTrust, to: CFStreamPropertyKey.self)
        guard let trustRef = CFReadStreamCopyProperty(readStream, peerTrustKey) else {
            return false
        }
        let trust = trustRef as! SecTrust
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = certificates.first
        else {
            finish(.failure(ShadowClientGameStreamError.invalidResponse))
            return false
        }

        let presentedDER = SecCertificateCopyData(leaf) as Data
        if let pinnedServerCertificateDER, presentedDER != pinnedServerCertificateDER {
            finish(.failure(ShadowClientGameStreamError.responseRejected(code: 401, message: "Server certificate mismatch")))
            return false
        }

        peerValidated = true
        return true
    }

    private func writePendingBytes() {
        guard let writeStream, requestOffset < requestData.count else { return }

        let bytesWritten = requestData.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return -1
            }
            return CFWriteStreamWrite(
                writeStream,
                baseAddress.advanced(by: requestOffset),
                requestData.count - requestOffset
            )
        }

        if bytesWritten < 0 {
            finish(.failure(streamError(from: readStream, fallback: writeStream)))
            return
        }

        requestOffset += bytesWritten
        if requestOffset >= requestData.count {
            timeoutStage = "response read"
            Self.logger.notice(
                "Secure HTTP request write complete host=\(self.requestHost, privacy: .public) connect-host=\(self.connectHost, privacy: .public) next-stage=\(self.timeoutStage, privacy: .public)"
            )
        }
    }

    private func readAvailableBytes() {
        guard let readStream else { return }

        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while CFReadStreamHasBytesAvailable(readStream) {
            let count = CFReadStreamRead(readStream, &buffer, buffer.count)
            if count > 0 {
                responseData.append(buffer, count: count)
            } else if count < 0 {
                finish(.failure(streamError(from: readStream, fallback: writeStream)))
                return
            } else {
                break
            }
        }
    }

    private func maybeCompleteResponse() {
        guard requestOffset >= requestData.count else { return }
        guard !responseData.isEmpty else { return }

        if headerTerminatorUpperBound == nil,
           let separatorRange = responseData.range(of: Data("\r\n\r\n".utf8))
        {
            headerTerminatorUpperBound = separatorRange.upperBound
            let headerData = responseData[..<separatorRange.upperBound]
            if let headerText = String(data: headerData, encoding: .utf8) {
                expectedResponseBodyLength = Self.contentLength(from: headerText)
            }
        }

        guard let headerTerminatorUpperBound else {
            return
        }

        if let expectedResponseBodyLength {
            let bodyLength = responseData.count - headerTerminatorUpperBound
            guard bodyLength >= expectedResponseBodyLength else {
                return
            }
        }

        completeIfPossible()
    }

    private func completeIfPossible() {
        guard requestOffset >= requestData.count else { return }
        guard !responseData.isEmpty else { return }

        do {
            let body = try ShadowClientGameStreamHTTPTransport.extractHTTPBody(from: responseData)
            finish(.success(body))
        } catch {
            finish(.failure(error))
        }
    }

    private static func contentLength(from headerText: String) -> Int? {
        for line in headerText.components(separatedBy: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                continue
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "content-length" else {
                continue
            }
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value)
        }
        return nil
    }

    private func finish(_ result: Result<Data, Error>) {
        guard !completed else { return }
        completed = true

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        if let readStream {
            CFReadStreamSetClient(readStream, 0, nil, nil)
            CFReadStreamSetDispatchQueue(readStream, nil)
            CFReadStreamClose(readStream)
        }
        if let writeStream {
            CFWriteStreamSetClient(writeStream, 0, nil, nil)
            CFWriteStreamSetDispatchQueue(writeStream, nil)
            CFWriteStreamClose(writeStream)
        }
        readStream = nil
        writeStream = nil

        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(with: result)
    }

    private func streamError(from readStream: CFReadStream?, fallback writeStream: CFWriteStream?) -> Error {
        if let readStream, let error = CFReadStreamCopyError(readStream) {
            return error as Error
        }
        if let writeStream, let error = CFWriteStreamCopyError(writeStream) {
            return error as Error
        }
        return ShadowClientGameStreamError.requestFailed("HTTPS transport failed")
    }

    private static let readCallback: CFReadStreamClientCallBack = { _, type, info in
        guard let info else { return }
        let transport = Unmanaged<ShadowClientSecureHTTPStreamTransport>
            .fromOpaque(info)
            .takeUnretainedValue()
        transport.handleRead(event: type)
    }

    private static let writeCallback: CFWriteStreamClientCallBack = { _, type, info in
        guard let info else { return }
        let transport = Unmanaged<ShadowClientSecureHTTPStreamTransport>
            .fromOpaque(info)
            .takeUnretainedValue()
        transport.handleWrite(event: type)
    }

    private static let streamContextRetain: @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer? = { info in
        guard let info else {
            return nil
        }
        _ = Unmanaged<ShadowClientSecureHTTPStreamTransport>
            .fromOpaque(info)
            .retain()
        return info
    }

    private static let streamContextRelease: @convention(c) (UnsafeMutableRawPointer?) -> Void = { info in
        guard let info else {
            return
        }
        Unmanaged<ShadowClientSecureHTTPStreamTransport>
            .fromOpaque(info)
            .release()
    }
}

private final class ShadowClientServerTrustURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pinnedServerCertificateDER: Data?
    private let clientCertificateCredential: URLCredential?
    private let lock = NSLock()
    private var recordedTLSFailure: ShadowClientGameStreamTLSFailure?

    init(
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?
    ) {
        self.pinnedServerCertificateDER = pinnedServerCertificateDER
        self.clientCertificateCredential = clientCertificateCredential
        super.init()
    }

    var tlsFailure: ShadowClientGameStreamTLSFailure? {
        lock.lock()
        defer { lock.unlock() }
        return recordedTLSFailure
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handleChallenge(challenge, completionHandler: completionHandler)
    }

    private func handleChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate {
            guard let clientCertificateCredential else {
                recordTLSFailure(.clientCertificateRequired)
                completionHandler(.rejectProtectionSpace, nil)
                return
            }
            completionHandler(.useCredential, clientCertificateCredential)
            return
        }

        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        guard
            let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
            let leafCertificate = certificateChain.first
        else {
            recordTLSFailure(.serverCertificateMismatch)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let presentedDER = SecCertificateCopyData(leafCertificate) as Data

        if let pinnedServerCertificateDER {
            guard presentedDER == pinnedServerCertificateDER else {
                recordTLSFailure(.serverCertificateMismatch)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        // Apollo commonly presents a self-signed leaf certificate and doesn't match the
        // public host name. Treat the leaf as the trust anchor and evaluate under basic X509
        // so we can apply our own TOFU/pinning policy instead of system CA/hostname rules.
        let trustPolicy = SecPolicyCreateBasicX509()
        SecTrustSetPolicies(serverTrust, trustPolicy)
        SecTrustSetAnchorCertificates(serverTrust, [leafCertificate] as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError) else {
            recordTLSFailure(.serverCertificateMismatch)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func recordTLSFailure(_ failure: ShadowClientGameStreamTLSFailure) {
        lock.lock()
        if recordedTLSFailure == nil {
            recordedTLSFailure = failure
        }
        lock.unlock()
    }
}

private enum ShadowClientPairingIdentityMaterialFactory {
    private static let rsaEncryptionOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01])
    private static let sha256WithRSAEncryptionOID = Data([0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B])
    private static let commonNameOID = Data([0x55, 0x04, 0x03])
    private static let basicConstraintsOID = Data([0x55, 0x1D, 0x13])
    private static let keyUsageOID = Data([0x55, 0x1D, 0x0F])
    private static let extendedKeyUsageOID = Data([0x55, 0x1D, 0x25])
    private static let clientAuthOID = Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02])
    static func generate(commonName: String = "shadow-client") throws -> ShadowClientPairingIdentityMaterial {
        let privateKeyAttributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: 2048,
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(privateKeyAttributes as CFDictionary, &error) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard let privateKeyDERValue = SecKeyCopyExternalRepresentation(privateKey, &error) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        guard let publicKeyDERValue = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        let privateKeyDER = privateKeyDERValue as Data
        let publicKeyDER = publicKeyDERValue as Data
        let certificateDER = try createSelfSignedCertificateDER(
            commonName: commonName,
            publicKeyRSADER: publicKeyDER,
            privateKey: privateKey
        )

        return ShadowClientPairingIdentityMaterial(
            certificatePEM: makePEM(blockType: "CERTIFICATE", der: certificateDER),
            privateKeyPEM: makePEM(blockType: "RSA PRIVATE KEY", der: privateKeyDER)
        )
    }

    private static func createSelfSignedCertificateDER(
        commonName: String,
        publicKeyRSADER: Data,
        privateKey: SecKey
    ) throws -> Data {
        let version = derContextSpecificExplicit(
            tag: 0,
            inner: derInteger(Data([0x02]))
        )
        let serial = derInteger(makeSerialNumber())
        let signatureAlgorithm = derSequence([
            derObjectIdentifier(sha256WithRSAEncryptionOID),
            derNull(),
        ])
        let issuer = derName(commonName: commonName)
        let validity = derSequence([
            derUTCTime(date: Date().addingTimeInterval(-300)),
            derUTCTime(date: Date().addingTimeInterval(60 * 60 * 24 * 365 * 20)),
        ])
        let subject = issuer
        let subjectPublicKeyInfo = derSequence([
            derSequence([
                derObjectIdentifier(rsaEncryptionOID),
                derNull(),
            ]),
            derBitString(publicKeyRSADER),
        ])
        let extensions = derContextSpecificExplicit(
            tag: 3,
            inner: derSequence([
                derSequence([
                    derObjectIdentifier(basicConstraintsOID),
                    derBoolean(false),
                    derOctetString(derSequence([])),
                ]),
                derSequence([
                    derObjectIdentifier(keyUsageOID),
                    derBoolean(true),
                    derOctetString(derBitString(Data([0x80]), unusedBitCount: 7)),
                ]),
                derSequence([
                    derObjectIdentifier(extendedKeyUsageOID),
                    derOctetString(
                        derSequence([
                            derObjectIdentifier(clientAuthOID),
                        ])
                    ),
                ]),
            ])
        )
        let tbsCertificate = derSequence([
            version,
            serial,
            signatureAlgorithm,
            issuer,
            validity,
            subject,
            subjectPublicKeyInfo,
            extensions,
        ])

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &error
        ) as Data? else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return derSequence([
            tbsCertificate,
            signatureAlgorithm,
            derBitString(signature),
        ])
    }

    private static func makeSerialNumber() -> Data {
        var serial = Data(count: 16)
        _ = serial.withUnsafeMutableBytes { rawBuffer in
            SecRandomCopyBytes(kSecRandomDefault, rawBuffer.count, rawBuffer.baseAddress!)
        }

        if serial.isEmpty {
            return Data([0x01])
        }

        if serial[serial.startIndex] == 0 {
            serial[serial.startIndex] = 0x01
        }

        return serial
    }

    private static func makePEM(blockType: String, der: Data) -> String {
        let body = der.base64EncodedString(
            options: [.lineLength64Characters, .endLineWithLineFeed]
        )
        let normalizedBody = body.hasSuffix("\n") ? body : "\(body)\n"
        return "-----BEGIN \(blockType)-----\n\(normalizedBody)-----END \(blockType)-----\n"
    }

    private static func der(_ tag: UInt8, _ value: Data) -> Data {
        var result = Data([tag])
        result.append(derLength(value.count))
        result.append(value)
        return result
    }

    private static func derLength(_ length: Int) -> Data {
        if length < 0x80 {
            return Data([UInt8(length)])
        }

        var bytes: [UInt8] = []
        var current = length
        while current > 0 {
            bytes.insert(UInt8(current & 0xFF), at: 0)
            current >>= 8
        }

        var encoded = Data([0x80 | UInt8(bytes.count)])
        encoded.append(contentsOf: bytes)
        return encoded
    }

    private static func derSequence(_ elements: [Data]) -> Data {
        der(0x30, elements.reduce(into: Data()) { partialResult, element in
            partialResult.append(element)
        })
    }

    private static func derSet(_ elements: [Data]) -> Data {
        der(0x31, elements.reduce(into: Data()) { partialResult, element in
            partialResult.append(element)
        })
    }

    private static func derInteger(_ bytes: Data) -> Data {
        var normalized = Data(bytes.drop { $0 == 0 })
        if normalized.isEmpty {
            normalized = Data([0])
        }

        var value = normalized
        if value[value.startIndex] & 0x80 != 0 {
            value.insert(0x00, at: value.startIndex)
        }

        return der(0x02, value)
    }

    private static func derObjectIdentifier(_ bytes: Data) -> Data {
        der(0x06, bytes)
    }

    private static func derNull() -> Data {
        der(0x05, Data())
    }

    private static func derBoolean(_ value: Bool) -> Data {
        der(0x01, Data([value ? 0xFF : 0x00]))
    }

    private static func derOctetString(_ value: Data) -> Data {
        der(0x04, value)
    }

    private static func derUTF8String(_ value: String) -> Data {
        der(0x0C, Data(value.utf8))
    }

    private static func derUTCTime(date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        return der(0x17, Data(formatter.string(from: date).utf8))
    }

    private static func derBitString(_ value: Data, unusedBitCount: UInt8 = 0) -> Data {
        var content = Data([unusedBitCount])
        content.append(value)
        return der(0x03, content)
    }

    private static func derContextSpecificExplicit(tag: UInt8, inner: Data) -> Data {
        der(0xA0 | tag, inner)
    }

    private static func derName(commonName: String) -> Data {
        let commonNameAttribute = derSequence([
            derObjectIdentifier(commonNameOID),
            derUTF8String(commonName),
        ])
        let relativeDistinguishedName = derSet([commonNameAttribute])
        return derSequence([relativeDistinguishedName])
    }
}

enum ShadowClientX509DER {
    static func signatureBytes(fromCertificateDER der: Data) throws -> Data {
        var topReader = ShadowClientDERReader(data: der)
        let certificateSequence = try topReader.readElement(expectedTag: 0x30)

        var certificateReader = ShadowClientDERReader(data: certificateSequence)
        _ = try certificateReader.readAnyElement() // tbsCertificate
        _ = try certificateReader.readAnyElement() // signatureAlgorithm
        let signatureBitString = try certificateReader.readElement(expectedTag: 0x03)

        guard !signatureBitString.isEmpty else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        let unusedBits = signatureBitString[signatureBitString.startIndex]
        guard unusedBits == 0 else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return Data(signatureBitString.dropFirst())
    }
}

private struct ShadowClientDERReader {
    private let data: Data
    private var offset: Int = 0

    init(data: Data) {
        self.data = data
        self.offset = data.startIndex
    }

    mutating func readAnyElement() throws -> Data {
        let (_, value) = try readTLV()
        return value
    }

    mutating func readElement(expectedTag: UInt8) throws -> Data {
        let (tag, value) = try readTLV()
        guard tag == expectedTag else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }
        return value
    }

    private mutating func readTLV() throws -> (UInt8, Data) {
        guard offset < data.endIndex else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        let tag = data[offset]
        offset += 1

        guard offset < data.endIndex else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        let firstLength = data[offset]
        offset += 1

        let length: Int
        if firstLength & 0x80 == 0 {
            length = Int(firstLength)
        } else {
            let byteCount = Int(firstLength & 0x7F)
            guard byteCount > 0, offset + byteCount <= data.endIndex else {
                throw ShadowClientGameStreamControlError.invalidKeyMaterial
            }

            var parsed = 0
            for _ in 0..<byteCount {
                parsed = (parsed << 8) | Int(data[offset])
                offset += 1
            }
            length = parsed
        }

        guard length >= 0, offset + length <= data.endIndex else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        let value = data[offset..<(offset + length)]
        offset += length
        return (tag, Data(value))
    }
}

private extension Data {
    init?(pemEncodedCertificate pem: String) {
        let joinedBase64Body = pem
            .components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return !trimmed.hasPrefix("-----BEGIN") &&
                    !trimmed.hasPrefix("-----END") &&
                    !trimmed.isEmpty
            }
            .joined()

        guard let der = Data(base64Encoded: joinedBase64Body) else {
            return nil
        }

        self = der
    }

    init?(hexString: String) {
        let cleaned = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count % 2 == 0 else {
            return nil
        }

        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            let pair = cleaned[index..<next]
            guard let value = UInt8(pair, radix: 16) else {
                return nil
            }
            bytes.append(value)
            index = next
        }

        self = Data(bytes)
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
