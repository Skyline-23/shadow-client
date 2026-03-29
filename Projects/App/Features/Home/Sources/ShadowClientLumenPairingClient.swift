import Foundation
import Security
import ShadowClientFeatureConnection

#if canImport(UIKit)
import UIKit
#endif

public enum ShadowClientLumenPairingStatus: String, Codable, Equatable, Sendable {
    case pending
    case approved
    case rejected
    case expired
}

public struct ShadowClientLumenPairingSession: Equatable, Sendable {
    public let pairingID: String
    public let userCode: String
    public let deviceName: String
    public let platform: String
    public let clientID: String
    public let trustedClientUUID: String?
    public let publicKeyPresent: Bool
    public let clientTrusted: Bool
    public let clientCertificateRequired: Bool
    public let status: ShadowClientLumenPairingStatus
    public let serverUniqueID: String?
    public let serviceType: String?
    public let controlHTTPSPort: Int?
    public let preferredControlHTTPSURL: String?
    public let controlHTTPSURLs: [String]
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
        status: ShadowClientLumenPairingStatus,
        serverUniqueID: String?,
        serviceType: String?,
        controlHTTPSPort: Int?,
        preferredControlHTTPSURL: String? = nil,
        controlHTTPSURLs: [String] = [],
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
        self.preferredControlHTTPSURL = preferredControlHTTPSURL
        self.controlHTTPSURLs = controlHTTPSURLs
        self.expiresInSeconds = expiresInSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }
}

public protocol ShadowClientLumenPairingClient: Sendable {
    func startPairing(
        host: String,
        httpsPort: Int,
        deviceName: String?,
        platform: String?
    ) async throws -> ShadowClientLumenPairingSession

    func fetchPairingStatus(
        host: String,
        httpsPort: Int,
        pairingID: String
    ) async throws -> ShadowClientLumenPairingSession
}

protocol ShadowClientLumenHTTPTransport: Sendable {
    func request(
        url: URL,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> ShadowClientGameStreamHTTPTransport.HTTPSResponse
}

struct NativeShadowClientLumenHTTPTransport: ShadowClientLumenHTTPTransport {
    func request(
        url: URL,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> ShadowClientGameStreamHTTPTransport.HTTPSResponse {
        try await ShadowClientGameStreamHTTPTransport.requestPinnedHTTPSResponse(
            url: url,
            requestData: requestData,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity,
            timeout: timeout
        )
    }
}

public struct NativeShadowClientLumenPairingClient: ShadowClientLumenPairingClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder
    private let transport: any ShadowClientLumenHTTPTransport

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared
    ) {
        self.init(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore,
            authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder(
                identityStore: identityStore,
                pinnedCertificateStore: pinnedCertificateStore
            ),
            transport: NativeShadowClientLumenHTTPTransport()
        )
    }

    init(
        identityStore: ShadowClientPairingIdentityStore,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore,
        authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder,
        transport: any ShadowClientLumenHTTPTransport
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.authenticationContextBuilder = authenticationContextBuilder
        self.transport = transport
    }

    public func startPairing(
        host: String,
        httpsPort: Int,
        deviceName: String? = nil,
        platform: String? = nil
    ) async throws -> ShadowClientLumenPairingSession {
        let clientID = await identityStore.uniqueID()
        let certificateData = try await identityStore.clientCertificatePEMData()
        let certificatePEM = String(decoding: certificateData, as: UTF8.self)
        let payload = LumenStartPairingPayload(
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
    ) async throws -> ShadowClientLumenPairingSession {
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
            body: Optional<LumenStartPairingPayload>.none
        )
    }

    static func parsePairingSession(data: Data) throws -> ShadowClientLumenPairingSession {
        let payload = try JSONDecoder().decode(LumenPairingEnvelope.self, from: data)
        return payload.pairing.session
    }

    private func requestPairingSession<Body: Encodable>(
        host: String,
        httpsPort: Int,
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Body?
    ) async throws -> ShadowClientLumenPairingSession {
        let requestContexts = try await authenticationContextBuilder.makePairingContexts(
            host: host,
            httpsPort: httpsPort
        )
        let encodedBody = try body.map { try JSONEncoder().encode($0) }
        var lastError: Error?

        for requestContext in requestContexts {
            let request = try requestContext.makeRequestData(
                path: path,
                method: method,
                queryItems: queryItems,
                headers: encodedBody == nil ? [:] : ["Content-Type": "application/json"],
                body: encodedBody
            )

            do {
                let response = try await transport.request(
                    url: request.url,
                    requestData: request.requestData,
                    pinnedServerCertificateDER: requestContext.pinnedServerCertificateDER,
                    clientCertificates: requestContext.clientCertificates,
                    clientCertificateIdentity: requestContext.clientCertificateIdentity,
                    timeout: ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
                )

                let pairingSession = try Self.parsePairingSession(data: response.body)
                await persistPresentedServerTrust(
                    requestEndpoint: requestContext.endpoint,
                    pairingSession: pairingSession,
                    certificateDER: response.presentedLeafCertificateDER
                )
                return pairingSession
            } catch let error as ShadowClientGameStreamError {
                lastError = error
            } catch {
                lastError = ShadowClientGameStreamHTTPTransport.requestFailureError(error)
            }
        }

        throw lastError ?? ShadowClientGameStreamError.requestFailed("Lumen pairing request failed.")
    }

    private func persistPresentedServerTrust(
        requestEndpoint: ShadowClientLumenEndpoint,
        pairingSession: ShadowClientLumenPairingSession,
        certificateDER: Data?
    ) async {
        guard let certificateDER else {
            return
        }

        var endpoints: [ShadowClientLumenEndpoint] = [requestEndpoint]
        if let controlHTTPSPort = pairingSession.controlHTTPSPort {
            endpoints.append(.init(host: requestEndpoint.host, httpsPort: controlHTTPSPort))
        }

        let advertisedEndpoints = pairingSession.controlHTTPSURLs.compactMap(Self.endpoint(fromControlURLString:))
        endpoints.append(contentsOf: advertisedEndpoints)
        if let preferredControlEndpoint = Self.endpoint(fromControlURLString: pairingSession.preferredControlHTTPSURL) {
            endpoints.insert(preferredControlEndpoint, at: 0)
        }

        var seenEndpoints = Set<String>()
        for endpoint in endpoints {
            let routeKey = "\(endpoint.host.lowercased()):\(endpoint.httpsPort)"
            guard seenEndpoints.insert(routeKey).inserted else {
                continue
            }

            await pinnedCertificateStore.setCertificateDER(
                certificateDER,
                forHost: endpoint.host,
                httpsPort: endpoint.httpsPort
            )
            if let normalizedServerUniqueID = Self.normalizedMachineID(pairingSession.serverUniqueID) {
                await pinnedCertificateStore.bindHost(
                    endpoint.host,
                    httpsPort: endpoint.httpsPort,
                    toMachineID: normalizedServerUniqueID
                )
                await pinnedCertificateStore.setCertificateDER(
                    certificateDER,
                    forMachineID: normalizedServerUniqueID
                )
            }
        }
    }

    private static func endpoint(fromControlURLString urlString: String?) -> ShadowClientLumenEndpoint? {
        guard
            let urlString,
            let url = URL(string: urlString),
            let host = url.host
        else {
            return nil
        }
        return .init(
            host: host,
            httpsPort: url.port ?? ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        )
    }

    private static func normalizedMachineID(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? nil : trimmed
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

private struct LumenPairingEnvelope: Decodable {
    let pairing: LumenPairingPayload
}

private struct LumenPairingPayload: Codable {
    let pairingID: String
    let userCode: String
    let deviceName: String
    let platform: String
    let clientID: String
    let trustedClientUUID: String?
    let publicKeyPresent: Bool
    let clientTrusted: Bool
    let clientCertificateRequired: Bool
    let status: ShadowClientLumenPairingStatus
    let serverUniqueID: String?
    let serviceType: String?
    let controlHTTPSPort: Int?
    let preferredControlHTTPSURL: String?
    let controlHTTPSURLs: [String]?
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
        case preferredControlHTTPSURL = "preferredControlHttpsUrl"
        case controlHTTPSURLs = "controlHttpsUrls"
        case expiresInSeconds
        case pollIntervalSeconds
    }

    var session: ShadowClientLumenPairingSession {
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
            preferredControlHTTPSURL: preferredControlHTTPSURL,
            controlHTTPSURLs: controlHTTPSURLs ?? [],
            expiresInSeconds: expiresInSeconds,
            pollIntervalSeconds: pollIntervalSeconds
        )
    }
}

private struct LumenStartPairingPayload: Encodable {
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
