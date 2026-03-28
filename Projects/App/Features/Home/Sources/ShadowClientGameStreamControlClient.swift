import Foundation
import Network
import os
import Security
import ShadowClientFeatureConnection
import ShadowClientFeatureSession

public enum ShadowClientRemotePairingState: Equatable, Sendable {
    case idle
    case pairing(host: String, code: String)
    case paired(String)
    case failed(String)
}

public extension ShadowClientRemotePairingState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case let .pairing(host, code):
            if code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Starting pairing with \(host)."
            }
            return "Pairing with \(host). Approve this device in Apollo using the displayed code."
        case let .paired(message):
            return message
        case let .failed(message):
            return "Failed - \(message)"
        }
    }

    var activeCode: String? {
        switch self {
        case let .pairing(_, code):
            let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedCode.isEmpty ? nil : trimmedCode
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
    case invalidKeyMaterial
    case launchRejected
    case malformedResponse
}

extension ShadowClientGameStreamControlError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidKeyMaterial:
            return "Client key material is invalid."
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
            case .launchRejected, .malformedResponse:
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
        static let pinnedMachineCertificates = "pairing.pinned.machineCertificates"
        static let hostMachineBindings = "pairing.pinned.hostMachineBindings"
    }

    private let defaults: UserDefaults
    private var cachedHostCertificates: [String: String]
    private var cachedMachineCertificates: [String: String]
    private var cachedHostMachineBindings: [String: String]
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.cachedHostCertificates = defaults.dictionary(forKey: DefaultsKeys.pinnedCertificates) as? [String: String] ?? [:]
        self.cachedMachineCertificates = defaults.dictionary(forKey: DefaultsKeys.pinnedMachineCertificates) as? [String: String] ?? [:]
        self.cachedHostMachineBindings = defaults.dictionary(forKey: DefaultsKeys.hostMachineBindings) as? [String: String] ?? [:]
        defaults.removeObject(forKey: "pairing.pinned.rejectedHosts")
    }

    public init(defaultsSuiteName: String) {
        let suiteDefaults = UserDefaults(suiteName: defaultsSuiteName) ?? .standard
        self.defaults = suiteDefaults
        self.cachedHostCertificates = suiteDefaults.dictionary(forKey: DefaultsKeys.pinnedCertificates) as? [String: String] ?? [:]
        self.cachedMachineCertificates = suiteDefaults.dictionary(forKey: DefaultsKeys.pinnedMachineCertificates) as? [String: String] ?? [:]
        self.cachedHostMachineBindings = suiteDefaults.dictionary(forKey: DefaultsKeys.hostMachineBindings) as? [String: String] ?? [:]
        suiteDefaults.removeObject(forKey: "pairing.pinned.rejectedHosts")
    }

    public func certificateDER(forHost host: String) -> Data? {
        certificateDER(
            forHost: host,
            httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        )
    }

    public func certificateDER(forHost host: String, httpsPort: Int?) -> Data? {
        guard let httpsPort else {
            return certificateDER(forHost: host)
        }

        let key = normalizedRoute(host, httpsPort: httpsPort)
        if let machineID = cachedHostMachineBindings[key],
           let machineCertificate = certificateDER(forMachineID: machineID) {
            return machineCertificate
        }

        if let value = cachedHostCertificates[key] {
            return Data(base64Encoded: value)
        }
        return nil
    }

    public func certificateDER(forMachineID machineID: String) -> Data? {
        let key = normalizedMachineID(machineID)
        guard let value = cachedMachineCertificates[key] else {
            return nil
        }
        return Data(base64Encoded: value)
    }

    public func setCertificateDER(_ der: Data, forHost host: String) {
        setCertificateDER(
            der,
            forHost: host,
            httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        )
    }

    public func setCertificateDER(_ der: Data, forHost host: String, httpsPort: Int?) {
        guard let httpsPort else {
            setCertificateDER(der, forHost: host)
            return
        }

        let key = normalizedRoute(host, httpsPort: httpsPort)
        cachedHostCertificates[key] = der.base64EncodedString()
        if let machineID = cachedHostMachineBindings[key] {
            cachedMachineCertificates[machineID] = der.base64EncodedString()
        }
        persist()
    }

    public func setCertificateDER(_ der: Data, forMachineID machineID: String) {
        let key = normalizedMachineID(machineID)
        guard !key.isEmpty else {
            return
        }
        cachedMachineCertificates[key] = der.base64EncodedString()
        persist()
    }

    public func bindHost(_ host: String, toMachineID machineID: String) {
        bindHost(
            host,
            httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
            toMachineID: machineID
        )
    }

    public func bindHost(_ host: String, httpsPort: Int?, toMachineID machineID: String) {
        guard let httpsPort else {
            bindHost(host, toMachineID: machineID)
            return
        }

        let normalizedRouteKey = normalizedRoute(host, httpsPort: httpsPort)
        let normalizedMachineKey = normalizedMachineID(machineID)
        guard !normalizedRouteKey.isEmpty, !normalizedMachineKey.isEmpty else {
            return
        }
        cachedHostMachineBindings[normalizedRouteKey] = normalizedMachineKey
        if let hostCertificate = cachedHostCertificates[normalizedRouteKey] {
            cachedMachineCertificates[normalizedMachineKey] = hostCertificate
        } else if let machineCertificate = cachedMachineCertificates[normalizedMachineKey] {
            cachedHostCertificates[normalizedRouteKey] = machineCertificate
        }
        persist()
    }

    public func machineID(forHost host: String) -> String? {
        machineID(
            forHost: host,
            httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        )
    }

    public func machineID(forHost host: String, httpsPort: Int?) -> String? {
        guard let httpsPort else {
            return machineID(forHost: host)
        }
        let key = normalizedRoute(host, httpsPort: httpsPort)
        return cachedHostMachineBindings[key]
    }

    public func isRejectedHost(_ host: String) -> Bool {
        false
    }

    public func markRejectedHost(_ host: String) {
        let _ = host
    }

    public func clearRejectedHost(_ host: String) {
        let _ = host
    }

    public func removeCertificate(forHost host: String) {
        removeCertificate(
            forHost: host,
            httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        )
    }

    public func removeCertificate(forHost host: String, httpsPort: Int?) {
        guard let httpsPort else {
            removeCertificate(forHost: host)
            return
        }

        let key = normalizedRoute(host, httpsPort: httpsPort)
        cachedHostCertificates.removeValue(forKey: key)
        cachedHostMachineBindings.removeValue(forKey: key)
        persist()
    }

    public func removeCertificates(forMachineID machineID: String) {
        let normalizedMachineKey = normalizedMachineID(machineID)
        guard !normalizedMachineKey.isEmpty else {
            return
        }

        cachedMachineCertificates.removeValue(forKey: normalizedMachineKey)
        let boundHosts = cachedHostMachineBindings.compactMap { host, boundMachineID in
            boundMachineID == normalizedMachineKey ? host : nil
        }
        for host in boundHosts {
            cachedHostMachineBindings.removeValue(forKey: host)
            cachedHostCertificates.removeValue(forKey: host)
        }
        persist()
    }

    private func normalizedRoute(_ host: String, httpsPort: Int) -> String {
        let normalizedPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: httpsPort
        )
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmedHost)
        let normalizedRouteHost: String
        if let url = URL(string: candidate), let parsedHost = url.host {
            normalizedRouteHost = parsedHost.lowercased()
        } else {
            normalizedRouteHost = trimmedHost.lowercased()
        }

        let routeHost: String
        if normalizedRouteHost.contains(":"),
           !normalizedRouteHost.hasPrefix("["),
           !normalizedRouteHost.hasSuffix("]") {
            routeHost = "[\(normalizedRouteHost)]"
        } else {
            routeHost = normalizedRouteHost
        }
        return "\(routeHost):\(normalizedPort)"
    }

    private func normalizedMachineID(_ machineID: String) -> String {
        machineID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func persist() {
        defaults.set(cachedHostCertificates, forKey: DefaultsKeys.pinnedCertificates)
        defaults.set(cachedMachineCertificates, forKey: DefaultsKeys.pinnedMachineCertificates)
        defaults.set(cachedHostMachineBindings, forKey: DefaultsKeys.hostMachineBindings)
        defaults.removeObject(forKey: "pairing.pinned.rejectedHosts")
    }
}

public actor NativeGameStreamControlClient: ShadowClientGameStreamControlClient {
    private static let launchLogger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "Launch"
    )
    private static let videoCodecSupport = ShadowClientVideoCodecSupport()

    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let defaultHTTPPort: Int
    private let defaultRequestTimeout: TimeInterval

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultRequestTimeout: TimeInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultRequestTimeout = defaultRequestTimeout
    }

    public func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        forceLaunch: Bool = false,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        try Self.validateExperimentalLaunchCodec(settings.preferredCodec)
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let uniqueID = await identityStore.uniqueID()
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        )
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
        let clientDisplayCharacteristics = await ShadowClientApolloClientDisplayCharacteristicsResolver.current(
            hdrEnabled: settings.enableHDR,
            scalePercent: settings.resolutionScalePercent,
            hiDPIEnabled: settings.requestHiDPI
        )
        Self.launchLogger.notice(
            "Launch display profile gamut=\(clientDisplayCharacteristics.gamut.rawValue, privacy: .public) transfer=\(clientDisplayCharacteristics.transfer.rawValue, privacy: .public) scale=\(clientDisplayCharacteristics.scalePercent, privacy: .public) hidpi=\(clientDisplayCharacteristics.hiDPIEnabled, privacy: .public) hdr=\(settings.enableHDR, privacy: .public) current-edr-headroom=\(clientDisplayCharacteristics.currentEDRHeadroom, privacy: .public) potential-edr-headroom=\(clientDisplayCharacteristics.potentialEDRHeadroom, privacy: .public) current-peak-nits=\(clientDisplayCharacteristics.currentPeakLuminanceNits, privacy: .public) potential-peak-nits=\(clientDisplayCharacteristics.potentialPeakLuminanceNits, privacy: .public)"
        )
        var parameters = Self.makeLaunchParameters(
            appID: appID,
            settings: settings,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: keyID,
            surroundAudioInfo: surroundAudioInfo,
            localAudioPlayMode: localAudioPlayMode,
            clientDisplayCharacteristics: clientDisplayCharacteristics
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
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: httpsPort)
        let uniqueID = await identityStore.uniqueID()
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        )
        let tlsClientCredential = try? await identityStore.tlsClientCertificateCredential()
        let tlsClientCertificates = try? await identityStore.tlsClientCertificates()
        let tlsClientIdentity = try? await identityStore.tlsClientIdentity()

        _ = try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: endpoint.host,
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
        makeLaunchParameters(
            appID: appID,
            settings: settings,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: remoteInputKeyID,
            surroundAudioInfo: surroundAudioInfo,
            localAudioPlayMode: localAudioPlayMode,
            clientDisplayCharacteristics: nil
        )
    }

    static func makeLaunchParameters(
        appID: Int,
        settings: ShadowClientGameStreamLaunchSettings,
        remoteInputKey: Data,
        remoteInputKeyID: UInt32,
        surroundAudioInfo: Int,
        localAudioPlayMode: String,
        clientDisplayCharacteristics: ShadowClientApolloClientDisplayCharacteristics?
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

        let sinkScalePercent = clientDisplayCharacteristics?.scalePercent ?? settings.resolutionScalePercent
        let sinkHiDPI = clientDisplayCharacteristics?.hiDPIEnabled ?? settings.requestHiDPI
        let sinkModeIsLogical = clientDisplayCharacteristics?.modeIsLogical ?? settings.requestHiDPI
        let requestedDynamicRangeTransport = clientDisplayCharacteristics?
            .requestedDynamicRangeTransport(hdrRequested: settings.enableHDR)
            .rawValue ?? (settings.enableHDR ? ShadowClientApolloDynamicRangeTransport.frameGatedHDR.rawValue : ShadowClientApolloDynamicRangeTransport.sdr.rawValue)
        let supportsFrameGatedHDR = clientDisplayCharacteristics?.supportsFrameGatedHDR ?? false
        let supportsHDRTileOverlay = clientDisplayCharacteristics?.supportsHDRTileOverlay ?? false
        let supportsPerFrameHDRMetadata = clientDisplayCharacteristics?.supportsPerFrameHDRMetadata ?? false

        if settings.preferVirtualDisplay {
            parameters["virtualDisplay"] = "1"
        }
        parameters["clientDisplayScalePercent"] = "\(settings.resolutionScalePercent)"
        parameters["clientDisplayHiDPI"] = settings.requestHiDPI ? "1" : "0"
        parameters["clientSinkScalePercent"] = "\(sinkScalePercent)"
        parameters["clientSinkHiDPI"] = ShadowClientApolloSinkContractProfile.boolString(sinkHiDPI)
        parameters["clientSinkModeIsLogical"] = ShadowClientApolloSinkContractProfile.boolString(sinkModeIsLogical)
        parameters["requestedDynamicRangeTransport"] = requestedDynamicRangeTransport
        parameters["clientSinkSupportsFrameGatedHDR"] = ShadowClientApolloSinkContractProfile.boolString(supportsFrameGatedHDR)
        parameters["clientSinkSupportsHDRTileOverlay"] = ShadowClientApolloSinkContractProfile.boolString(supportsHDRTileOverlay)
        parameters["clientSinkSupportsPerFrameHDRMetadata"] = ShadowClientApolloSinkContractProfile.boolString(supportsPerFrameHDRMetadata)
        if settings.resolutionScalePercent != 100 {
            parameters["scaleFactor"] = "\(settings.resolutionScalePercent)"
        }
        if let clientDisplayCharacteristics {
            parameters["clientDisplayGamut"] = clientDisplayCharacteristics.gamut.rawValue
            parameters["clientDisplayTransfer"] = clientDisplayCharacteristics.transfer.rawValue
            parameters["clientDisplayCurrentEDRHeadroom"] = "\(clientDisplayCharacteristics.currentEDRHeadroom)"
            parameters["clientDisplayPotentialEDRHeadroom"] = "\(clientDisplayCharacteristics.potentialEDRHeadroom)"
            parameters["clientDisplayCurrentPeakLuminanceNits"] = "\(clientDisplayCharacteristics.currentPeakLuminanceNits)"
            parameters["clientDisplayPotentialPeakLuminanceNits"] = "\(clientDisplayCharacteristics.potentialPeakLuminanceNits)"
            parameters["clientSinkGamut"] = clientDisplayCharacteristics.gamut.rawValue
            parameters["clientSinkTransfer"] = clientDisplayCharacteristics.transfer.rawValue
            parameters["clientSinkCurrentEDRHeadroom"] = "\(clientDisplayCharacteristics.currentEDRHeadroom)"
            parameters["clientSinkPotentialEDRHeadroom"] = "\(clientDisplayCharacteristics.potentialEDRHeadroom)"
            parameters["clientSinkCurrentPeakLuminanceNits"] = "\(clientDisplayCharacteristics.currentPeakLuminanceNits)"
            parameters["clientSinkPotentialPeakLuminanceNits"] = "\(clientDisplayCharacteristics.potentialPeakLuminanceNits)"
        }

        return parameters
    }

    public func setClipboard(
        host: String,
        httpsPort: Int,
        text: String
    ) async throws {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        )
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
        let pinnedServerCertificate = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        )
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
        case .h265, .h264, .prores:
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

    private static func validateExperimentalLaunchCodec(
        _ preferredCodec: ShadowClientVideoCodecPreference
    ) throws {
        guard preferredCodec.requiresCustomHostSupport else {
            return
        }

        throw ShadowClientGameStreamError.requestFailed(
            "ProRes is experimental in shadow and requires a custom host codec lane. Stock Sunshine/GameStream hosts are not supported yet."
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

    private static func parseHostEndpoint(host: String, fallbackPort: Int) throws -> (host: String, port: Int) {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
        guard let url = URL(string: candidate), let parsedHost = url.host else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let resolvedPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: url.port ?? fallbackPort
        )
        return (parsedHost, resolvedPort)
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
    // Preserve the protocol token expected by Apollo/GameStream endpoints.
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
            if scheme == ShadowClientGameStreamNetworkDefaults.httpsScheme {
                return try await requestPinnedHTTPSXML(
                    url: url,
                    pinnedServerCertificateDER: pinnedServerCertificateDER,
                    clientCertificates: clientCertificates,
                    clientCertificateIdentity: clientCertificateIdentity,
                    timeout: timeout
                )
            } else {
                return try await requestPlainHTTPXML(
                    url: url,
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
        timeout: TimeInterval
    ) async throws -> String {
        guard let host = url.host,
              let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 80))
        else {
            throw ShadowClientGameStreamError.invalidURL
        }

        let connection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )
        do {
            try await waitForReady(connection, timeout: timeout)
        } catch let urlError as URLError where urlError.code == .timedOut {
            logger.error(
                "Plain HTTP connection ready timed out host=\(host, privacy: .public) port=\(port.rawValue, privacy: .public)"
            )
            throw ShadowClientGameStreamError.requestFailed("connection ready timed out")
        } catch let gameStreamError as ShadowClientGameStreamError {
            logger.error(
                "Plain HTTP connection ready failed host=\(host, privacy: .public) port=\(port.rawValue, privacy: .public) error=\(gameStreamError.localizedDescription, privacy: .public)"
            )
            throw gameStreamError
        } catch {
            logger.error(
                "Plain HTTP connection ready failed host=\(host, privacy: .public) port=\(port.rawValue, privacy: .public) error=\(requestFailureMessage(error), privacy: .public)"
            )
            throw requestFailureError(error)
        }
        defer {
            connection.cancel()
        }

        let requestData = makePlainHTTPRequestData(url: url, host: host)
        try await send(requestData, over: connection)
        let responseData: Data
        do {
            responseData = try await receiveHTTPResponse(over: connection, timeout: timeout)
        } catch let urlError as URLError where urlError.code == .timedOut {
            logger.error(
                "Plain HTTP response receive timed out host=\(host, privacy: .public) port=\(port.rawValue, privacy: .public)"
            )
            throw ShadowClientGameStreamError.requestFailed("response receive timed out")
        }
        let body = try extractHTTPBody(from: responseData)
        guard let xml = String(data: body, encoding: .utf8), !xml.isEmpty else {
            throw ShadowClientGameStreamError.malformedXML
        }
        return xml
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
        return try await ShadowClientSecureHTTPStreamTransport.requestData(
            url: url,
            host: host,
            requestData: requestData,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity,
            timeout: timeout
        )
    }

    private static func requestPinnedHTTPSXML(
        url: URL,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> String {
        guard let host = url.host else {
            throw ShadowClientGameStreamError.invalidURL
        }
        return try await ShadowClientSecureHTTPStreamTransport.requestXML(
            url: url,
            host: host,
            requestData: makeHTTPRequestData(url: url, host: host, method: "GET"),
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity,
            timeout: timeout
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

        final class WaitingErrorTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var waitingError: Error?

            func update(_ error: Error) {
                lock.lock()
                waitingError = error
                lock.unlock()
            }

            func current() -> Error? {
                lock.lock()
                defer { lock.unlock() }
                return waitingError
            }
        }

        let gate = ResumeGate()
        let waitingErrorTracker = WaitingErrorTracker()
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
                case let .waiting(error):
                    waitingErrorTracker.update(error)
                    if shouldFailConnectionReadyImmediately(error) {
                        resume(.failure(error))
                    }
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
                if let waitingError = waitingErrorTracker.current() {
                    resume(
                        .failure(
                            ShadowClientGameStreamError.requestFailed(
                                "connection ready stalled while waiting: \(requestFailureMessage(waitingError))"
                            )
                        )
                    )
                } else {
                    resume(.failure(URLError(.timedOut)))
                }
            }
        }
    }

    static func shouldFailConnectionReadyImmediately(_ error: Error) -> Bool {
        if let networkError = error as? NWError,
           case let .posix(code) = networkError
        {
            switch code {
            case .ECONNREFUSED, .ECONNRESET, .EHOSTUNREACH, .ENETUNREACH:
                return true
            default:
                return false
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            switch nsError.code {
            case Int(ECONNREFUSED), Int(ECONNRESET), Int(EHOSTUNREACH), Int(ENETUNREACH):
                return true
            default:
                break
            }
        }

        return false
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
    private let host: String
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
        host: String,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) {
        self.url = url
        self.host = host
        self.pinnedServerCertificateDER = pinnedServerCertificateDER
        self.clientCertificates = clientCertificates
        self.clientCertificateIdentity = clientCertificateIdentity
        self.timeout = timeout
        self.requestData = requestData
    }

    static func requestData(
        url: URL,
        host: String,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> Data {
        let transport = ShadowClientSecureHTTPStreamTransport(
            url: url,
            host: host,
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
        host: String,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> String {
        let responseData = try await ShadowClientSecureHTTPStreamTransport.requestData(
            url: url,
            host: host,
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
            host as CFString,
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
            let diagnostics = self.timeoutDiagnostics()
            Self.logger.error(
                "Secure HTTP timed out host=\(self.host, privacy: .public) port=\(self.url.port ?? 443, privacy: .public) stage=\(self.timeoutStage, privacy: .public) diagnostics=\(diagnostics, privacy: .public)"
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
            timeoutStage = writeOpen ? "peer validation" : "read stream open"
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
            timeoutStage = readOpen ? "peer validation" : "write stream open"
            validatePeerIfPossible()
        case .canAcceptBytes:
            guard validatePeerIfPossible() else { return }
            timeoutStage = "request write"
            Self.logger.notice(
                "Secure HTTP writable host=\(self.host, privacy: .public) stage=\(self.timeoutStage, privacy: .public)"
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

    private func timeoutDiagnostics() -> String {
        let readStatus = readStream.map { Self.streamStatusDescription(CFReadStreamGetStatus($0)) } ?? "missing"
        let writeStatus = writeStream.map { Self.streamStatusDescription(CFWriteStreamGetStatus($0)) } ?? "missing"
        let readError = readStream
            .flatMap { CFReadStreamCopyError($0) as Error? }
            .map(\.localizedDescription) ?? "none"
        let writeError = writeStream
            .flatMap { CFWriteStreamCopyError($0) as Error? }
            .map(\.localizedDescription) ?? "none"
        return [
            "readOpen=\(readOpen)",
            "writeOpen=\(writeOpen)",
            "peerValidated=\(peerValidated)",
            "readStatus=\(readStatus)",
            "writeStatus=\(writeStatus)",
            "readError=\(readError)",
            "writeError=\(writeError)",
        ].joined(separator: " ")
    }

    private static func streamStatusDescription(_ status: CFStreamStatus) -> String {
        switch status {
        case .notOpen:
            return "notOpen"
        case .opening:
            return "opening"
        case .open:
            return "open"
        case .reading:
            return "reading"
        case .writing:
            return "writing"
        case .atEnd:
            return "atEnd"
        case .closed:
            return "closed"
        case .error:
            return "error"
        @unknown default:
            return "unknown"
        }
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
                "Secure HTTP request write complete host=\(self.host, privacy: .public) next-stage=\(self.timeoutStage, privacy: .public)"
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
