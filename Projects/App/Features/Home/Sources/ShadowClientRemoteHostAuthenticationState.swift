import Foundation

public enum ShadowClientRemoteHostPairingAuthState: Equatable, Sendable {
    case pendingResolution
    case unavailable(String)
    case paired
    case pairingRequired
    case reachable
}

public enum ShadowClientRemoteHostAdminAuthState: Equatable, Sendable {
    case unavailable
    case idle
    case loading
    case saving
    case ready(profileLoaded: Bool)
    case failed(String)
}

public struct ShadowClientRemoteHostAuthenticationState: Equatable, Sendable {
    public let pairing: ShadowClientRemoteHostPairingAuthState
    public let admin: ShadowClientRemoteHostAdminAuthState
    public let isStreaming: Bool

    public init(
        pairing: ShadowClientRemoteHostPairingAuthState,
        admin: ShadowClientRemoteHostAdminAuthState,
        isStreaming: Bool
    ) {
        self.pairing = pairing
        self.admin = admin
        self.isStreaming = isStreaming
    }

    public static func hostState(
        for host: ShadowClientRemoteHostDescriptor,
        adminState currentAdminState: ShadowClientLumenAdminClientState = .idle,
        adminProfile: ShadowClientLumenAdminClientProfile? = nil
    ) -> ShadowClientRemoteHostAuthenticationState {
        let pairing = pairingState(for: host)
        return .init(
            pairing: pairing,
            admin: resolveAdminState(
                for: pairing,
                adminState: currentAdminState,
                adminProfile: adminProfile
            ),
            isStreaming: host.currentGameID > 0
        )
    }

    public var statusLabel: String {
        if isStreaming {
            return "Streaming"
        }

        switch pairing {
        case .pendingResolution:
            return "Saved"
        case .unavailable:
            return "Unavailable"
        case .paired:
            return "Ready"
        case .pairingRequired:
            return "Pairing Required"
        case .reachable:
            return "Reachable"
        }
    }

    public var detailLabel: String {
        if isStreaming {
            return "Active game is running."
        }

        switch pairing {
        case .pendingResolution:
            return "Address saved. Host metadata will update when the server responds."
        case let .unavailable(message):
            return message
        case .paired:
            return "Pair status verified"
        case .pairingRequired:
            return "Host reachable. Pair this client in Lumen to continue."
        case .reachable:
            return "Host reachable"
        }
    }

    public var canPair: Bool {
        switch pairing {
        case .paired, .pendingResolution:
            return false
        case .unavailable, .pairingRequired, .reachable:
            return true
        }
    }

    public var canRefreshApps: Bool {
        pairing == .paired
    }

    public var canConnect: Bool {
        pairing == .paired
    }

    public var hostIndicatorTone: ShadowClientRemoteHostAuthenticationTone {
        if isStreaming {
            return .streaming
        }

        switch pairing {
        case .pendingResolution, .reachable:
            return .neutral
        case .unavailable:
            return .unavailable
        case .paired:
            return .ready
        case .pairingRequired:
            return .pairingRequired
        }
    }

    public var adminStatusLabel: String {
        switch admin {
        case .unavailable:
            return "Available after pairing"
        case .idle:
            return "Not synced"
        case .loading:
            return "Loading…"
        case .saving:
            return "Saving…"
        case let .ready(profileLoaded):
            return profileLoaded ? "Loaded" : "Client not found"
        case let .failed(message):
            return message
        }
    }

    private static func pairingState(
        for host: ShadowClientRemoteHostDescriptor
    ) -> ShadowClientRemoteHostPairingAuthState {
        if host.isPendingResolution {
            return .pendingResolution
        }

        if let lastError = host.lastError?.trimmingCharacters(in: .whitespacesAndNewlines),
           !lastError.isEmpty
        {
            return .unavailable(lastError)
        }

        switch host.pairStatus {
        case .paired:
            return .paired
        case .notPaired:
            return .pairingRequired
        case .unknown:
            return .reachable
        }
    }

    private static func resolveAdminState(
        for pairing: ShadowClientRemoteHostPairingAuthState,
        adminState: ShadowClientLumenAdminClientState,
        adminProfile: ShadowClientLumenAdminClientProfile?
    ) -> ShadowClientRemoteHostAdminAuthState {
        guard pairing == .paired else {
            return .unavailable
        }

        switch adminState {
        case .idle:
            return .idle
        case .loading:
            return .loading
        case .saving:
            return .saving
        case .loaded:
            return .ready(profileLoaded: adminProfile != nil)
        case let .failed(message):
            return .failed(message)
        }
    }
}

public enum ShadowClientRemoteHostAuthenticationTone: Equatable, Sendable {
    case neutral
    case unavailable
    case ready
    case pairingRequired
    case streaming
}

public extension ShadowClientRemoteHostDescriptor {
    var authenticationState: ShadowClientRemoteHostAuthenticationState {
        .hostState(for: self)
    }

    func authenticationState(
        adminState: ShadowClientLumenAdminClientState,
        adminProfile: ShadowClientLumenAdminClientProfile?
    ) -> ShadowClientRemoteHostAuthenticationState {
        .hostState(
            for: self,
            adminState: adminState,
            adminProfile: adminProfile
        )
    }
}
