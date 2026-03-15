import SwiftUI

public struct ShadowClientConnectionPresentationKit {
    public static func canInitiateSessionConnection(state: ShadowClientConnectionState) -> Bool {
        switch state {
        case .connecting, .disconnecting:
            return false
        case .connected, .disconnected, .failed:
            return true
        }
    }

    public static func canConnect(
        normalizedHost: String,
        state: ShadowClientConnectionState
    ) -> Bool {
        guard !normalizedHost.isEmpty else {
            return false
        }
        return canInitiateSessionConnection(state: state)
    }

    public static func canDisconnect(state: ShadowClientConnectionState) -> Bool {
        switch state {
        case .connected, .connecting, .failed:
            return true
        case .disconnected, .disconnecting:
            return false
        }
    }

    public static func statusText(state: ShadowClientConnectionState) -> String {
        switch state {
        case .disconnected:
            return "Status: Disconnected"
        case let .connecting(host):
            return "Status: Connecting to \(host)..."
        case let .connected(host):
            return "Status: Connected to \(host)"
        case .disconnecting:
            return "Status: Disconnecting..."
        case let .failed(_, message):
            return "Status: Connection Failed - \(message)"
        }
    }

    public static func statusColor(state: ShadowClientConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .failed:
            return .red
        case .connecting, .disconnecting:
            return .orange
        case .disconnected:
            return .secondary
        }
    }

    public static func statusSymbol(state: ShadowClientConnectionState) -> String {
        switch state {
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .connecting, .disconnecting:
            return "clock.fill"
        case .disconnected:
            return "bolt.slash.fill"
        }
    }
}
