import CommonCrypto
import CryptoKit
import Foundation
import os
import Security

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
            return "Pairing with \(host). Enter displayed PIN in Sunshine."
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
}

public enum ShadowClientRemoteLaunchState: Equatable, Sendable {
    case idle
    case launching
    case launched(String)
    case failed(String)
}

public extension ShadowClientRemoteLaunchState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .launching:
            return "Launching"
        case let .launched(message):
            return message
        case let .failed(message):
            return "Failed - \(message)"
        }
    }
}

public enum ShadowClientVideoCodecPreference: String, CaseIterable, Equatable, Sendable {
    case auto
    case av1
    case h265
    case h264

    var launchParameterValue: String? {
        switch self {
        case .auto:
            return nil
        case .av1:
            return "av1"
        case .h265:
            return "hevc"
        case .h264:
            return "h264"
        }
    }
}

public struct ShadowClientGameStreamLaunchSettings: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bitrateKbps: Int
    public let preferredCodec: ShadowClientVideoCodecPreference
    public let enableHDR: Bool
    public let enableSurroundAudio: Bool
    public let lowLatencyMode: Bool
    public let enableVSync: Bool
    public let enableFramePacing: Bool
    public let enableYUV444: Bool
    public let unlockBitrateLimit: Bool
    public let forceHardwareDecoding: Bool
    public let optimizeGameSettingsForStreaming: Bool
    public let quitAppOnHostAfterStreamEnds: Bool
    public let playAudioOnHost: Bool

    public init(
        width: Int = ShadowClientStreamingLaunchBounds.defaultWidth,
        height: Int = ShadowClientStreamingLaunchBounds.defaultHeight,
        fps: Int = ShadowClientStreamingLaunchBounds.defaultFPS,
        bitrateKbps: Int = ShadowClientStreamingLaunchBounds.defaultBitrateKbps,
        preferredCodec: ShadowClientVideoCodecPreference = .auto,
        enableHDR: Bool,
        enableSurroundAudio: Bool,
        lowLatencyMode: Bool,
        enableVSync: Bool = false,
        enableFramePacing: Bool = false,
        enableYUV444: Bool = false,
        unlockBitrateLimit: Bool = false,
        forceHardwareDecoding: Bool = true,
        optimizeGameSettingsForStreaming: Bool = true,
        quitAppOnHostAfterStreamEnds: Bool = false,
        playAudioOnHost: Bool = false
    ) {
        self.width = max(ShadowClientStreamingLaunchBounds.minimumWidth, width)
        self.height = max(ShadowClientStreamingLaunchBounds.minimumHeight, height)
        self.fps = max(ShadowClientStreamingLaunchBounds.minimumFPS, fps)
        self.bitrateKbps = min(
            max(ShadowClientStreamingLaunchBounds.minimumBitrateKbps, bitrateKbps),
            ShadowClientStreamingLaunchBounds.maximumBitrateKbps
        )
        self.preferredCodec = preferredCodec
        self.enableHDR = enableHDR
        self.enableSurroundAudio = enableSurroundAudio
        self.lowLatencyMode = lowLatencyMode
        self.enableVSync = enableVSync
        self.enableFramePacing = enableFramePacing
        self.enableYUV444 = enableYUV444
        self.unlockBitrateLimit = unlockBitrateLimit
        self.forceHardwareDecoding = forceHardwareDecoding
        self.optimizeGameSettingsForStreaming = optimizeGameSettingsForStreaming
        self.quitAppOnHostAfterStreamEnds = quitAppOnHostAfterStreamEnds
        self.playAudioOnHost = playAudioOnHost
    }
}

public struct ShadowClientGameStreamLaunchResult: Equatable, Sendable {
    public let sessionURL: String?
    public let verb: String
    public let remoteInputKey: Data?
    public let remoteInputKeyID: UInt32?

    public init(
        sessionURL: String?,
        verb: String,
        remoteInputKey: Data? = nil,
        remoteInputKeyID: UInt32? = nil
    ) {
        self.sessionURL = sessionURL
        self.verb = verb
        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
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

    public init(certificatePEM: String, privateKeyPEM: String) {
        self.certificatePEM = certificatePEM
        self.privateKeyPEM = privateKeyPEM
    }
}

public protocol ShadowClientPairingIdentityProviding {
    func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial
}

enum ShadowClientPairingIdentityDefaultsKeys {
    static let certificatePEM = "pairing.identity.certificatePEM"
    static let privateKeyPEM = "pairing.identity.privateKeyPEM"
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
            privateKeyPEM: privateKeyPEM
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
    func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        forceLaunch: Bool,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult
}

public extension ShadowClientGameStreamControlClient {
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
        let certDER = try pemBodyData(pem: material.certificatePEM)
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

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

        let identity = makeKeychainBackedIdentity(
            certificate: certificate,
            privateKey: privateKey,
            certificateDER: certDER
        ) ?? SecIdentityCreate(nil, certificate, privateKey)

        guard let identity else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

        return URLCredential(
            identity: identity,
            certificates: [certificate],
            persistence: .forSession
        )
    }

    private func makeKeychainBackedIdentity(
        certificate: SecCertificate,
        privateKey: SecKey,
        certificateDER: Data
    ) -> SecIdentity? {
        let fingerprint = Data(SHA256.hash(data: certificateDER)).hexString
        let keyTag = Data("shadow-client.tls.key.\(fingerprint)".utf8)
        let certLabel = "shadow-client.tls.cert.\(fingerprint)"

        let addKeyQuery: [CFString: Any] = [
            kSecClass: kSecClassKey,
            kSecAttrApplicationTag: keyTag,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecAttrIsPermanent: true,
            kSecValueRef: privateKey,
        ]
        let keyStatus = SecItemAdd(addKeyQuery as CFDictionary, nil)
        guard keyStatus == errSecSuccess || keyStatus == errSecDuplicateItem else {
            return nil
        }

        let addCertQuery: [CFString: Any] = [
            kSecClass: kSecClassCertificate,
            kSecAttrLabel: certLabel,
            kSecValueRef: certificate,
        ]
        let certStatus = SecItemAdd(addCertQuery as CFDictionary, nil)
        guard certStatus == errSecSuccess || certStatus == errSecDuplicateItem else {
            return nil
        }

        let identityQuery: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecAttrLabel: certLabel,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var identityRef: CFTypeRef?
        let identityStatus = SecItemCopyMatching(identityQuery as CFDictionary, &identityRef)
        guard
            identityStatus == errSecSuccess,
            let identityRef
        else {
            return nil
        }
        guard CFGetTypeID(identityRef) == SecIdentityGetTypeID() else {
            return nil
        }
        return unsafeDowncast(identityRef, to: SecIdentity.self)
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
        let uniqueID = await identityStore.uniqueID()
        // Build TLS credential first so any material recovery happens before stage1 uploads client cert.
        let tlsClientCredential = try await identityStore.tlsClientCertificateCredential()
        let certPEMData = try await identityStore.clientCertificatePEMData()
        let clientCertSignature = try await identityStore.clientCertificateSignature()

        let hashAlgorithm = PairHashAlgorithm.from(appVersion: appVersion)
        let salt = Self.randomBytes(length: 16)
        let saltedPin = Data(salt + Data(trimmedPIN.utf8))
        let aesKey = Data(hashAlgorithm.digest(saltedPin).prefix(16))

        let stage1XML = try await requestPairXML(
            stage: "getservercert",
            host: endpoint.host,
            port: endpoint.port,
            scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "phrase": "getservercert",
                "salt": salt.hexString,
                "clientcert": certPEMData.hexString,
            ],
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

        let resolvedHTTPSPort = httpsPort ?? defaultHTTPSPort
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
                pinnedServerCertificateDER: serverCertDER,
                clientCertificateCredential: tlsClientCredential,
                timeout: pairingStageTimeout
            )
            let stage5Doc = try parsePairStageXML(stage5XML, stage: "pairchallenge")
            guard stage5Doc.values["paired"]?.first == "1" else {
                try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
                throw ShadowClientGameStreamControlError.challengeRejected
            }
        } catch {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw error
        }

        await pinnedCertificateStore.setCertificateDER(serverCertDER, forHost: endpoint.host)
        return ShadowClientGameStreamPairingResult(host: endpoint.host)
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

        let remoteInputKey = Self.randomBytes(length: 16)
        let remoteInputIV = Self.randomBytes(length: 16)
        let keyID = remoteInputIV.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }

        let isSurround = settings.enableSurroundAudio && !settings.lowLatencyMode
        let surroundAudioInfo = isSurround ? 393_279 : 131_075
        let localAudioPlayMode = settings.playAudioOnHost ? "1" : "0"

        var parameters: [String: String] = [
            "appid": "\(appID)",
            "mode": "\(settings.width)x\(settings.height)x\(settings.fps)",
            "additionalStates": "1",
            "sops": "1",
            "rikey": remoteInputKey.hexString,
            "rikeyid": "\(keyID)",
            "localAudioPlayMode": localAudioPlayMode,
            "surroundAudioInfo": "\(surroundAudioInfo)",
            "remoteControllersBitmap": "1",
            "gcmap": "1",
            "gcpersist": "0",
        ]

        parameters["bitrate"] = "\(settings.bitrateKbps)"

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
            // Sunshine/GameStream stacks don't fully agree on this key, so send both.
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
                "Pairing timed out while waiting for Sunshine PIN confirmation. Enter the displayed PIN on the host and retry."
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
    // Preserve the legacy protocol token expected by Sunshine/GameStream endpoints.
    private static let shadowClientCompatibleUniqueID = "0123456789ABCDEF"

    static func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential? = nil,
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

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        var trustDelegate: ShadowClientServerTrustURLSessionDelegate?
        let session: URLSession
        if scheme == ShadowClientGameStreamNetworkDefaults.httpsScheme {
            let delegate = ShadowClientServerTrustURLSessionDelegate(
                pinnedServerCertificateDER: pinnedServerCertificateDER,
                clientCertificateCredential: clientCertificateCredential
            )
            trustDelegate = delegate
            session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        } else {
            session = .shared
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw Self.requestFailureError(error, tlsFailure: trustDelegate?.tlsFailure)
        }

        guard response is HTTPURLResponse else {
            throw ShadowClientGameStreamError.invalidResponse
        }

        guard let xml = String(data: data, encoding: .utf8), !xml.isEmpty else {
            throw ShadowClientGameStreamError.malformedXML
        }

        return xml
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

    private static func requestFailureMessage(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .appTransportSecurityRequiresSecureConnection {
            return "Insecure HTTP is blocked by App Transport Security for this request."
        }

        return error.localizedDescription
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

        if let pinnedServerCertificateDER {
            guard
                let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                let leafCertificate = certificateChain.first
            else {
                recordTLSFailure(.serverCertificateMismatch)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            let presentedDER = SecCertificateCopyData(leafCertificate) as Data
            guard presentedDER == pinnedServerCertificateDER else {
                recordTLSFailure(.serverCertificateMismatch)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
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
        let tbsCertificate = derSequence([
            version,
            serial,
            signatureAlgorithm,
            issuer,
            validity,
            subject,
            subjectPublicKeyInfo,
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

    private static func derBitString(_ value: Data) -> Data {
        var content = Data([0x00])
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
