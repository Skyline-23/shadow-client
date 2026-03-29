import SwiftUI

enum ShadowClientRemoteHostActionKit {
    static func canPair(selectedHost: ShadowClientRemoteHostDescriptor?) -> Bool {
        guard let selectedHost else {
            return false
        }
        return canPair(host: selectedHost)
    }

    static func canPair(host: ShadowClientRemoteHostDescriptor) -> Bool {
        host.authenticationState.canPair
    }

    static func canRefreshApps(selectedHost: ShadowClientRemoteHostDescriptor?) -> Bool {
        guard let selectedHost else {
            return false
        }
        return selectedHost.authenticationState.canRefreshApps
    }

    static func canConnect(
        host: ShadowClientRemoteHostDescriptor,
        canInitiateSessionConnection: Bool
    ) -> Bool {
        canInitiateSessionConnection && host.authenticationState.canConnect
    }

    static func shouldShowPairAction(host: ShadowClientRemoteHostDescriptor) -> Bool {
        canPair(host: host)
    }

    static func rowActionColor(
        host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool,
        accentColor: Color
    ) -> Color {
        switch host.authenticationState.hostIndicatorTone {
        case .neutral:
            return isSelected ? accentColor : Color.white.opacity(0.72)
        case .unavailable:
            return .red.opacity(0.92)
        case .ready:
            return .mint
        case .pairingRequired:
            return .yellow
        case .streaming:
            return .orange
        }
    }
}
