import Foundation
import ShadowClientFeatureConnection

public struct ShadowClientLumenAdminClientProfile: Equatable, Sendable {
    public struct Command: Equatable, Sendable, Codable {
        public let cmd: String
        public let elevated: Bool

        public init(cmd: String, elevated: Bool) {
            self.cmd = cmd
            self.elevated = elevated
        }
    }

    public let name: String
    public let uuid: String
    public let displayModeOverride: String
    public let alwaysUseVirtualDisplay: Bool
    public let connected: Bool
    public let doCommands: [Command]
    public let undoCommands: [Command]

    public init(
        name: String = "",
        uuid: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool,
        connected: Bool,
        doCommands: [Command] = [],
        undoCommands: [Command] = []
    ) {
        self.name = name
        self.uuid = uuid
        self.displayModeOverride = displayModeOverride
        self.alwaysUseVirtualDisplay = alwaysUseVirtualDisplay
        self.connected = connected
        self.doCommands = doCommands
        self.undoCommands = undoCommands
    }
}

public protocol ShadowClientLumenAdminClient: Sendable {
    func fetchCurrentClientProfile(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenAdminClientProfile?

    func updateCurrentClientProfile(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        profile: ShadowClientLumenAdminClientProfile
    ) async throws -> ShadowClientLumenAdminClientProfile

    func disconnectCurrentClient(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        uuid: String
    ) async throws

    func unpairCurrentClient(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        uuid: String
    ) async throws

    func approvePairingRequest(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        pairingID: String
    ) async throws
}

public extension ShadowClientLumenAdminClient {
    func fetchCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenAdminClientProfile? {
        try await fetchCurrentClientProfile(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password
        )
    }

    func updateCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        profile: ShadowClientLumenAdminClientProfile
    ) async throws -> ShadowClientLumenAdminClientProfile {
        try await updateCurrentClientProfile(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password,
            profile: profile
        )
    }

    func disconnectCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        try await disconnectCurrentClient(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password,
            uuid: uuid
        )
    }

    func unpairCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        try await unpairCurrentClient(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password,
            uuid: uuid
        )
    }

    func approvePairingRequest(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        pairingID: String
    ) async throws {
        try await approvePairingRequest(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password,
            pairingID: pairingID
        )
    }
}

public struct NativeShadowClientLumenAdminClient: ShadowClientLumenAdminClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder
    private let transport: any ShadowClientLumenHTTPTransport

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared
    ) {
        self.init(
            identityStore: identityStore,
            authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder(
                identityStore: identityStore,
                pinnedCertificateStore: pinnedCertificateStore
            ),
            transport: NativeShadowClientLumenHTTPTransport()
        )
    }

    init(
        identityStore: ShadowClientPairingIdentityStore,
        authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder,
        transport: any ShadowClientLumenHTTPTransport
    ) {
        self.identityStore = identityStore
        self.authenticationContextBuilder = authenticationContextBuilder
        self.transport = transport
    }

    public func fetchCurrentClientProfile(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenAdminClientProfile? {
        let response = try await performAdminRequest(
            route: route,
            username: username,
            password: password,
            path: "/api/clients/list",
            method: "GET"
        )
        let currentClientUUID = await identityStore.uniqueID()
        return try Self.parseCurrentClientProfile(
            data: response.body,
            currentClientUUID: currentClientUUID
        )
    }

    public func updateCurrentClientProfile(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        profile: ShadowClientLumenAdminClientProfile
    ) async throws -> ShadowClientLumenAdminClientProfile {
        _ = try await performAdminRequest(
            route: route,
            username: username,
            password: password,
            path: "/api/clients/update",
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(
                LumenUpdateClientPayload(
                    uuid: profile.uuid,
                    name: profile.name,
                    displayMode: profile.displayModeOverride,
                    alwaysUseVirtualDisplay: profile.alwaysUseVirtualDisplay,
                    doCommands: profile.doCommands,
                    undoCommands: profile.undoCommands
                )
            )
        )
        return profile
    }

    public func disconnectCurrentClient(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        try await postSimpleClientAction(
            route: route,
            username: username,
            password: password,
            path: "/api/clients/disconnect",
            body: LumenUUIDPayload(uuid: uuid)
        )
    }

    public func unpairCurrentClient(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        try await postSimpleClientAction(
            route: route,
            username: username,
            password: password,
            path: "/api/clients/unpair",
            body: LumenUUIDPayload(uuid: uuid)
        )
    }

    public func approvePairingRequest(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        pairingID: String
    ) async throws {
        let trimmedPairingID = pairingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPairingID.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Pairing ID is required.")
        }

        try await postSimpleClientAction(
            route: route,
            username: username,
            password: password,
            path: "/api/pairing/approve",
            body: LumenPairingDecisionPayload(pairingID: trimmedPairingID)
        )
    }

    static func parseCurrentClientProfile(
        data: Data,
        currentClientUUID: String
    ) throws -> ShadowClientLumenAdminClientProfile? {
        let payload = try JSONDecoder().decode(LumenClientsListPayload.self, from: data)
        return payload.namedCerts.first {
            $0.uuid.caseInsensitiveCompare(currentClientUUID) == .orderedSame
        }?.profile
    }

    private func postSimpleClientAction<Body: Encodable>(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        path: String,
        body: Body
    ) async throws {
        _ = try await performAdminRequest(
            route: route,
            username: username,
            password: password,
            path: path,
            method: "POST",
            headers: ["Content-Type": "application/json"],
            body: try JSONEncoder().encode(body)
        )
    }

    private func performAdminRequest(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        path: String,
        method: String,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> ShadowClientGameStreamHTTPTransport.HTTPSResponse {
        let requestContexts = try await authenticationContextBuilder.makeAdminContexts(
            route: route,
            username: username,
            password: password
        )
        var lastError: Error?

        for requestContext in requestContexts {
            let request = try requestContext.makeRequestData(
                path: path,
                method: method,
                headers: headers,
                body: body
            )

            do {
                return try await performRequest(
                    request,
                    requestContext: requestContext
                )
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ShadowClientGameStreamError.requestFailed("Lumen admin request failed.")
    }

    private func performRequest(
        _ request: ShadowClientLumenPreparedHTTPSRequest,
        requestContext: ShadowClientLumenHTTPSRequestContext
    ) async throws -> ShadowClientGameStreamHTTPTransport.HTTPSResponse {
        do {
            return try await transport.request(
                url: request.url,
                connectHost: request.connectHost,
                requestData: request.requestData,
                pinnedServerCertificateDER: requestContext.pinnedServerCertificateDER,
                clientCertificates: requestContext.clientCertificates,
                clientCertificateIdentity: requestContext.clientCertificateIdentity,
                timeout: ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
            )
        } catch let error as ShadowClientGameStreamError {
            throw error
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(error)
        }
    }
}

private struct LumenClientsListPayload: Decodable {
    let namedCerts: [LumenNamedCert]

    enum CodingKeys: String, CodingKey {
        case namedCerts = "named_certs"
    }
}

private struct LumenNamedCert: Decodable {
    let name: String
    let uuid: String
    let displayMode: String
    let alwaysUseVirtualDisplay: Bool
    let connected: Bool
    let doCommands: [LumenCommand]
    let undoCommands: [LumenCommand]

    enum CodingKeys: String, CodingKey {
        case name
        case uuid
        case displayMode = "display_mode"
        case alwaysUseVirtualDisplay = "always_use_virtual_display"
        case connected
        case doCommands = "do"
        case undoCommands = "undo"
    }

    var profile: ShadowClientLumenAdminClientProfile {
        .init(
            name: name,
            uuid: uuid,
            displayModeOverride: displayMode,
            alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
            connected: connected,
            doCommands: doCommands.map(\.profileCommand),
            undoCommands: undoCommands.map(\.profileCommand)
        )
    }
}

private struct LumenCommand: Codable {
    let cmd: String
    let elevated: Bool

    var profileCommand: ShadowClientLumenAdminClientProfile.Command {
        .init(cmd: cmd, elevated: elevated)
    }
}

private struct LumenUpdateClientPayload: Encodable {
    let uuid: String
    let name: String
    let displayMode: String
    let alwaysUseVirtualDisplay: Bool
    let doCommands: [ShadowClientLumenAdminClientProfile.Command]
    let undoCommands: [ShadowClientLumenAdminClientProfile.Command]

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case displayMode = "display_mode"
        case alwaysUseVirtualDisplay = "always_use_virtual_display"
        case doCommands = "do"
        case undoCommands = "undo"
    }
}

private struct LumenUUIDPayload: Encodable {
    let uuid: String
}

private struct LumenPairingDecisionPayload: Encodable {
    let pairingID: String

    enum CodingKeys: String, CodingKey {
        case pairingID = "pairingId"
    }
}
