import SwiftUI

enum ShadowClientRemoteHostActionKit {
    static func canPair(selectedHost: ShadowClientRemoteHostDescriptor?) -> Bool {
        guard let selectedHost else {
            return false
        }
        return selectedHost.isReachable && selectedHost.pairStatus != .paired
    }

    static func canRefreshApps(selectedHost: ShadowClientRemoteHostDescriptor?) -> Bool {
        guard let selectedHost else {
            return false
        }
        return selectedHost.isReachable && selectedHost.pairStatus == .paired
    }

    static func canConnect(
        host: ShadowClientRemoteHostDescriptor,
        canInitiateSessionConnection: Bool
    ) -> Bool {
        canInitiateSessionConnection && host.isReachable && host.pairStatus == .paired
    }

    static func shouldShowPairAction(host: ShadowClientRemoteHostDescriptor) -> Bool {
        host.isReachable && host.pairStatus != .paired
    }

    static func rowActionColor(
        host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool,
        accentColor: Color
    ) -> Color {
        if host.isPendingResolution {
            return Color.white.opacity(0.72)
        }
        if !host.isReachable {
            return .red.opacity(0.92)
        }
        if isSelected {
            return accentColor
        }
        switch host.pairStatus {
        case .paired:
            return .mint
        case .notPaired:
            return .yellow
        case .unknown:
            return Color.white.opacity(0.72)
        }
    }
}
