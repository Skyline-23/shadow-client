import CommonCrypto
import CryptoKit
import Foundation
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

public struct ShadowClientGameStreamLaunchSettings: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let fps: Int
    public let enableHDR: Bool
    public let enableSurroundAudio: Bool
    public let lowLatencyMode: Bool

    public init(
        width: Int = 1920,
        height: Int = 1080,
        fps: Int = 60,
        enableHDR: Bool,
        enableSurroundAudio: Bool,
        lowLatencyMode: Bool
    ) {
        self.width = max(640, width)
        self.height = max(360, height)
        self.fps = max(30, fps)
        self.enableHDR = enableHDR
        self.enableSurroundAudio = enableSurroundAudio
        self.lowLatencyMode = lowLatencyMode
    }
}

public struct ShadowClientGameStreamLaunchResult: Equatable, Sendable {
    public let sessionURL: String?
    public let verb: String

    public init(sessionURL: String?, verb: String) {
        self.sessionURL = sessionURL
        self.verb = verb
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
    func pair(host: String, pin: String, appVersion: String?) async throws -> ShadowClientGameStreamPairingResult
    func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult
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
        let material = try resolveMaterial()
        let certDER = try pemBodyData(pem: material.certificatePEM)
        return try ShadowClientX509DER.signatureBytes(fromCertificateDER: certDER)
    }

    public func sign(_ message: Data) throws -> Data {
        let material = try resolveMaterial()
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
        guard SecCertificateCreateWithData(nil, certDER as CFData) != nil else {
            throw ShadowClientGameStreamControlError.invalidKeyMaterial
        }

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

        return material
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
        defaultHTTPPort: Int = 47989,
        defaultHTTPSPort: Int = 47984,
        defaultRequestTimeout: TimeInterval = 8,
        pairingPINEntryTimeout: TimeInterval = 90,
        pairingStageTimeout: TimeInterval = 15
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultHTTPSPort = defaultHTTPSPort
        self.defaultRequestTimeout = defaultRequestTimeout
        self.pairingPINEntryTimeout = pairingPINEntryTimeout
        self.pairingStageTimeout = pairingStageTimeout
    }

    public func pair(host: String, pin: String, appVersion: String?) async throws -> ShadowClientGameStreamPairingResult {
        let trimmedPIN = pin.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPIN.count >= 4 else {
            throw ShadowClientGameStreamControlError.invalidPIN
        }

        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let uniqueID = await identityStore.uniqueID()
        let certPEMData = try await identityStore.clientCertificatePEMData()
        let clientCertSignature = try await identityStore.clientCertificateSignature()

        let hashAlgorithm = PairHashAlgorithm.from(appVersion: appVersion)
        let salt = Self.randomBytes(length: 16)
        let saltedPin = Data(salt + Data(trimmedPIN.utf8))
        let aesKey = Data(hashAlgorithm.digest(saltedPin).prefix(16))

        let stage1XML: String
        do {
            stage1XML = try await ShadowClientGameStreamHTTPTransport.requestXML(
                host: endpoint.host,
                port: endpoint.port,
                scheme: "http",
                command: "pair",
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
        } catch let error as ShadowClientGameStreamError {
            throw Self.remapPairingStageError(error, stage: "getservercert")
        }

        let stage1Doc = try parsePairResponseXML(stage1XML)
        guard stage1Doc.values["paired"]?.first == "1" else {
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        guard
            let plainCertHex = stage1Doc.values["plaincert"]?.first,
            let serverCertDER = Data(hexString: plainCertHex)
        else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.pairingAlreadyInProgress
        }

        let randomChallenge = Self.randomBytes(length: 16)
        let encryptedChallenge = try Self.cryptAES(
            input: randomChallenge,
            key: aesKey,
            operation: CCOperation(kCCEncrypt)
        )

        let stage2XML = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: endpoint.host,
            port: endpoint.port,
            scheme: "http",
            command: "pair",
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "clientchallenge": encryptedChallenge.hexString,
            ],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
        let stage2Doc = try parsePairResponseXML(stage2XML)
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

        let stage3XML = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: endpoint.host,
            port: endpoint.port,
            scheme: "http",
            command: "pair",
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "serverchallengeresp": encryptedResponseHash.hexString,
            ],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
        let stage3Doc = try parsePairResponseXML(stage3XML)
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

        let stage4XML = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: endpoint.host,
            port: endpoint.port,
            scheme: "http",
            command: "pair",
            parameters: [
                "devicename": "shadow-client",
                "updateState": "1",
                "clientpairingsecret": clientPairingSecret.hexString,
            ],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: nil,
            timeout: pairingStageTimeout
        )
        let stage4Doc = try parsePairResponseXML(stage4XML)
        guard stage4Doc.values["paired"]?.first == "1" else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        let stage5Parameters: [String: String] = [
            "devicename": "shadow-client",
            "updateState": "1",
            "phrase": "pairchallenge",
        ]
        let stage5Attempts: [(scheme: String, port: Int, pinned: Data?)] = [
            (scheme: "https", port: defaultHTTPSPort, pinned: serverCertDER),
            (scheme: "http", port: endpoint.port, pinned: nil),
        ]

        var stage5Error: Error?
        var stage5Succeeded = false
        for attempt in stage5Attempts {
            do {
                let stage5XML = try await ShadowClientGameStreamHTTPTransport.requestXML(
                    host: endpoint.host,
                    port: attempt.port,
                    scheme: attempt.scheme,
                    command: "pair",
                    parameters: stage5Parameters,
                    uniqueID: uniqueID,
                    pinnedServerCertificateDER: attempt.pinned,
                    timeout: pairingStageTimeout
                )
                let stage5Doc = try parsePairResponseXML(stage5XML)
                guard stage5Doc.values["paired"]?.first == "1" else {
                    stage5Error = ShadowClientGameStreamControlError.challengeRejected
                    continue
                }

                stage5Succeeded = true
                break
            } catch {
                stage5Error = error
                continue
            }
        }

        guard stage5Succeeded else {
            try? await sendUnpair(host: endpoint.host, port: endpoint.port, uniqueID: uniqueID)
            if let stage5Error {
                throw stage5Error
            }
            throw ShadowClientGameStreamControlError.challengeRejected
        }

        await pinnedCertificateStore.setCertificateDER(serverCertDER, forHost: endpoint.host)
        return ShadowClientGameStreamPairingResult(host: endpoint.host)
    }

    public func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let uniqueID = await identityStore.uniqueID()
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(forHost: endpoint.host)

        let remoteInputKey = Self.randomBytes(length: 16)
        let remoteInputIV = Self.randomBytes(length: 16)
        let keyID = remoteInputIV.prefix(4).reduce(UInt32(0)) { partial, byte in
            (partial << 8) | UInt32(byte)
        }

        let isSurround = settings.enableSurroundAudio && !settings.lowLatencyMode
        let surroundAudioInfo = isSurround ? 393_279 : 131_075
        let verb = currentGameID == 0 ? "launch" : "resume"

        var parameters: [String: String] = [
            "appid": "\(appID)",
            "mode": "\(settings.width)x\(settings.height)x\(settings.fps)",
            "additionalStates": "1",
            "sops": "1",
            "rikey": remoteInputKey.hexString,
            "rikeyid": "\(keyID)",
            "localAudioPlayMode": "1",
            "surroundAudioInfo": "\(surroundAudioInfo)",
            "remoteControllersBitmap": "1",
            "gcmap": "1",
            "gcpersist": "0",
        ]

        if settings.enableHDR {
            parameters["hdrMode"] = "1"
            parameters["clientHdrCapVersion"] = "0"
            parameters["clientHdrCapSupportedFlagsInUint32"] = "0"
            parameters["clientHdrCapMetaDataId"] = "NV_STATIC_METADATA_TYPE_1"
            parameters["clientHdrCapDisplayData"] = "0x0x0x0x0x0x0x0x0x0x0"
        }

        var capturedError: Error?
        let attempts: [(scheme: String, port: Int, pinned: Data?)] = [
            (scheme: "https", port: httpsPort, pinned: pinnedServerCertificate),
            (scheme: "http", port: endpoint.port, pinned: nil),
        ]

        for attempt in attempts {
            do {
                let xml = try await ShadowClientGameStreamHTTPTransport.requestXML(
                    host: endpoint.host,
                    port: attempt.port,
                    scheme: attempt.scheme,
                    command: verb,
                    parameters: parameters,
                    uniqueID: uniqueID,
                    pinnedServerCertificateDER: attempt.pinned,
                    timeout: defaultRequestTimeout
                )

                let document = try ShadowClientXMLFlatDocumentParser.parse(xml: xml)
                try Self.validateRootStatus(document.rootStatus)
                let sessionURL = document.values["sessionUrl0"]?.first
                return ShadowClientGameStreamLaunchResult(sessionURL: sessionURL, verb: verb)
            } catch {
                capturedError = error
            }
        }

        if let capturedError = capturedError as? ShadowClientGameStreamError {
            throw capturedError
        }

        if let capturedError = capturedError {
            throw ShadowClientGameStreamError.requestFailed(capturedError.localizedDescription)
        }

        throw ShadowClientGameStreamControlError.launchRejected
    }

    private func parsePairResponseXML(_ xml: String) throws -> ShadowClientXMLFlatDocument {
        let document = try ShadowClientXMLFlatDocumentParser.parse(xml: xml)
        try Self.validateRootStatus(document.rootStatus)
        return document
    }

    private func sendUnpair(host: String, port: Int, uniqueID: String) async throws {
        _ = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: host,
            port: port,
            scheme: "http",
            command: "unpair",
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

        let candidate = normalized.contains("://") ? normalized : "http://\(normalized)"
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
                return error
            }

            return .requestFailed(
                "Pairing timed out while waiting for Sunshine PIN confirmation. Enter the displayed PIN on the host and retry."
            )
        default:
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

enum ShadowClientGameStreamHTTPTransport {
    static func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        timeout: TimeInterval = 8
    ) async throws -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = port
        components.path = "/\(command)"

        var queryItems: [URLQueryItem] = parameters
            .sorted(by: { $0.key < $1.key })
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(.init(name: "uniqueid", value: uniqueID))
        queryItems.append(.init(name: "uuid", value: UUID().uuidString))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout

        let session: URLSession
        if scheme == "https" {
            let delegate = ShadowClientServerTrustURLSessionDelegate(
                pinnedServerCertificateDER: pinnedServerCertificateDER
            )
            session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        } else {
            session = .shared
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ShadowClientGameStreamError.requestFailed(Self.requestFailureMessage(error))
        }

        guard response is HTTPURLResponse else {
            throw ShadowClientGameStreamError.invalidResponse
        }

        guard let xml = String(data: data, encoding: .utf8), !xml.isEmpty else {
            throw ShadowClientGameStreamError.malformedXML
        }

        return xml
    }

    private static func requestFailureMessage(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .appTransportSecurityRequiresSecureConnection {
            return "Insecure HTTP is blocked by App Transport Security for this request."
        }

        return error.localizedDescription
    }
}

private final class ShadowClientServerTrustURLSessionDelegate: NSObject, URLSessionDelegate {
    private let pinnedServerCertificateDER: Data?

    init(pinnedServerCertificateDER: Data?) {
        self.pinnedServerCertificateDER = pinnedServerCertificateDER
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if let pinnedServerCertificateDER {
            guard
                let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
                let leafCertificate = certificateChain.first
            else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }

            let presentedDER = SecCertificateCopyData(leafCertificate) as Data
            guard presentedDER == pinnedServerCertificateDER else {
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
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
