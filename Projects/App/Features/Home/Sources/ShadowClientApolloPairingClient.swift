import Foundation
import Security
import ShadowClientFeatureConnection

#if canImport(UIKit)
import UIKit
#endif

public enum ShadowClientApolloPairingStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case rejected
    case expired
}

public struct ShadowClientApolloPairingSession: Equatable, Sendable {
    public let pairingID: String
    public let userCode: String
    public let deviceName: String
    public let platform: String
    public let clientID: String
    public let trustedClientUUID: String?
    public let publicKeyPresent: Bool
    public let clientTrusted: Bool
    public let clientCertificateRequired: Bool
    public let status: ShadowClientApolloPairingStatus
    public let serverUniqueID: String?
    public let serviceType: String?
    public let controlHTTPSPort: Int?
    public let expiresInSeconds: Int
    public let pollIntervalSeconds: Int

    public init(
        pairingID: String,
        userCode: String,
        deviceName: String,
        platform: String,
        clientID: String,
        trustedClientUUID: String?,
        publicKeyPresent: Bool,
        clientTrusted: Bool,
        clientCertificateRequired: Bool,
        status: ShadowClientApolloPairingStatus,
        serverUniqueID: String?,
        serviceType: String?,
        controlHTTPSPort: Int?,
        expiresInSeconds: Int,
        pollIntervalSeconds: Int
    ) {
        self.pairingID = pairingID
        self.userCode = userCode
        self.deviceName = deviceName
        self.platform = platform
        self.clientID = clientID
        self.trustedClientUUID = trustedClientUUID
        self.publicKeyPresent = publicKeyPresent
        self.clientTrusted = clientTrusted
        self.clientCertificateRequired = clientCertificateRequired
        self.status = status
        self.serverUniqueID = serverUniqueID
        self.serviceType = serviceType
        self.controlHTTPSPort = controlHTTPSPort
        self.expiresInSeconds = expiresInSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

public protocol ShadowClientApolloPairingClient: Sendable {
    func startPairing(
        host: String,
        httpsPort: Int,
        deviceName: String?,
        platform: String?
    ) async throws -> ShadowClientApolloPairingSession

    func fetchPairingStatus(
        host: String,
        httpsPort: Int,
        pairingID: String
    ) async throws -> ShadowClientApolloPairingSession
}

public struct NativeShadowClientApolloPairingClient: ShadowClientApolloPairingClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
    }

    public func startPairing(
        host: String,
        httpsPort: Int,
        deviceName: String? = nil,
        platform: String? = nil
    ) async throws -> ShadowClientApolloPairingSession {
        let clientID = await identityStore.uniqueID()
        let certificateData = try await identityStore.clientCertificatePEMData()
        let certificatePEM = String(decoding: certificateData, as: UTF8.self)
        let payload = ApolloStartPairingPayload(
            deviceName: Self.resolvedDeviceName(from: deviceName),
            platform: Self.resolvedPlatform(from: platform),
            clientID: clientID,
            clientCertificate: certificatePEM
        )

        let session = try await requestPairingSession(
            host: host,
            httpsPort: httpsPort,
            path: "/api/pairing/start",
            method: "POST",
            queryItems: [],
            body: payload
        )
        return session
    }

    public func fetchPairingStatus(
        host: String,
        httpsPort: Int,
        pairingID: String
    ) async throws -> ShadowClientApolloPairingSession {
        let trimmedPairingID = pairingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPairingID.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Pairing ID is required.")
        }

        return try await requestPairingSession(
            host: host,
            httpsPort: httpsPort,
            path: "/api/pairing/status",
            method: "GET",
            queryItems: [
                .init(name: "pairingId", value: trimmedPairingID),
            ],
            body: Optional<ApolloStartPairingPayload>.none
        )
    }

    static func parsePairingSession(data: Data) throws -> ShadowClientApolloPairingSession {
        let payload = try JSONDecoder().decode(ApolloPairingEnvelope.self, from: data)
        return payload.pairing.session
    }

    private func requestPairingSession<Body: Encodable>(
        host: String,
        httpsPort: Int,
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Body?
    ) async throws -> ShadowClientApolloPairingSession {
        let endpoint = try Self.parseHostEndpoint(
            host: host,
            fallbackPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPPort
        )
        let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        )
        let delegate = ShadowClientApolloPairingURLSessionDelegate(
            pinnedServerCertificateDER: pinnedCertificateDER
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = endpoint.host
        components.port = httpsPort
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ShadowClientGameStreamError.invalidResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw ShadowClientGameStreamError.responseRejected(
                    code: httpResponse.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            }

            let pairingSession = try Self.parsePairingSession(data: data)
            await persistPresentedServerTrust(
                host: endpoint.host,
                httpsPort: httpsPort,
                serverUniqueID: pairingSession.serverUniqueID,
                certificateDER: delegate.presentedLeafCertificateDER
            )
            return pairingSession
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(
                error,
                tlsFailure: delegate.tlsFailure
            )
        }
    }

    private func persistPresentedServerTrust(
        host: String,
        httpsPort: Int,
        serverUniqueID: String?,
        certificateDER: Data?
    ) async {
        guard let certificateDER else {
            return
        }

        await pinnedCertificateStore.setCertificateDER(
            certificateDER,
            forHost: host,
            httpsPort: httpsPort
        )
        if let normalizedServerUniqueID = Self.normalizedMachineID(serverUniqueID) {
            await pinnedCertificateStore.bindHost(
                host,
                httpsPort: httpsPort,
                toMachineID: normalizedServerUniqueID
            )
            await pinnedCertificateStore.setCertificateDER(
                certificateDER,
                forMachineID: normalizedServerUniqueID
            )
        }
    }

    private static func normalizedMachineID(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseHostEndpoint(
        host: String,
        fallbackPort: Int
    ) throws -> (host: String, port: Int) {
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

    private static func resolvedDeviceName(from override: String?) -> String {
        if let trimmedOverride = override?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedOverride.isEmpty {
            return trimmedOverride
        }

#if canImport(UIKit)
        let currentName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return currentName.isEmpty ? "Shadow Client" : currentName
#else
        let fallback = (Host.current().localizedName ?? ProcessInfo.processInfo.hostName)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Shadow Client" : fallback
#endif
    }

    private static func resolvedPlatform(from override: String?) -> String {
        if let trimmedOverride = override?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmedOverride.isEmpty {
            return trimmedOverride
        }

#if os(tvOS)
        return "tvos"
#elseif os(iOS)
        return "ios"
#elseif os(macOS)
        return "macos"
#else
        return "unknown"
#endif
    }
}

private struct ApolloPairingEnvelope: Decodable {
    let pairing: ApolloPairingPayload
}

private struct ApolloPairingPayload: Codable {
    let pairingID: String
    let userCode: String
    let deviceName: String
    let platform: String
    let clientID: String
    let trustedClientUUID: String?
    let publicKeyPresent: Bool
    let clientTrusted: Bool
    let clientCertificateRequired: Bool
    let status: ShadowClientApolloPairingStatus
    let serverUniqueID: String?
    let serviceType: String?
    let controlHTTPSPort: Int?
    let expiresInSeconds: Int
    let pollIntervalSeconds: Int

    enum CodingKeys: String, CodingKey {
        case pairingID = "pairingId"
        case userCode
        case deviceName
        case platform
        case clientID = "clientId"
        case trustedClientUUID = "trustedClientUuid"
        case publicKeyPresent
        case clientTrusted
        case clientCertificateRequired
        case status
        case serverUniqueID = "serverUniqueId"
        case serviceType
        case controlHTTPSPort = "controlHttpsPort"
        case expiresInSeconds
        case pollIntervalSeconds
    }

    var session: ShadowClientApolloPairingSession {
        .init(
            pairingID: pairingID,
            userCode: userCode,
            deviceName: deviceName,
            platform: platform,
            clientID: clientID,
            trustedClientUUID: trustedClientUUID,
            publicKeyPresent: publicKeyPresent,
            clientTrusted: clientTrusted,
            clientCertificateRequired: clientCertificateRequired,
            status: status,
            serverUniqueID: serverUniqueID,
            serviceType: serviceType,
            controlHTTPSPort: controlHTTPSPort,
            expiresInSeconds: expiresInSeconds,
            pollIntervalSeconds: pollIntervalSeconds
        )
    }
}

private struct ApolloStartPairingPayload: Encodable {
    let deviceName: String
    let platform: String
    let clientID: String
    let clientCertificate: String

    enum CodingKeys: String, CodingKey {
        case deviceName
        case platform
        case clientID = "clientId"
        case clientCertificate
    }
}

private final class ShadowClientApolloPairingURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pinnedServerCertificateDER: Data?
    private let lock = NSLock()
    private var recordedTLSFailure: ShadowClientGameStreamTLSFailure?
    private var recordedPresentedLeafCertificateDER: Data?

    init(pinnedServerCertificateDER: Data?) {
        self.pinnedServerCertificateDER = pinnedServerCertificateDER
        super.init()
    }

    var tlsFailure: ShadowClientGameStreamTLSFailure? {
        lock.lock()
        defer { lock.unlock() }
        return recordedTLSFailure
    }

    var presentedLeafCertificateDER: Data? {
        lock.lock()
        defer { lock.unlock() }
        return recordedPresentedLeafCertificateDER
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    private func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCertificate = certificateChain.first
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let leafDER = SecCertificateCopyData(leafCertificate) as Data
        lock.lock()
        recordedPresentedLeafCertificateDER = leafDER
        lock.unlock()

        if let pinnedServerCertificateDER, leafDER != pinnedServerCertificateDER {
            recordTLSFailure(.serverCertificateMismatch)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func recordTLSFailure(_ failure: ShadowClientGameStreamTLSFailure) {
        lock.lock()
        recordedTLSFailure = failure
        lock.unlock()
    }
}
