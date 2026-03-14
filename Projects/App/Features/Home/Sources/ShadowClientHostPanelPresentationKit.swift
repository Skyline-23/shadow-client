import Foundation

struct ShadowClientHostPanelHeaderBadge: Equatable {
    let title: String
    let symbol: String
}

enum ShadowClientHostPanelPresentationKit {
    static func headerTitle() -> String {
        "Remote Desktop Hosts"
    }

    static func headerBadge(autoFindHosts: Bool) -> ShadowClientHostPanelHeaderBadge {
        if autoFindHosts {
            return .init(title: "Auto Scan", symbol: "dot.radiowaves.left.and.right")
        }
        return .init(title: "Manual", symbol: "plus.circle")
    }

    static func manualEntryTitle() -> String {
        "Add device"
    }

    static func emptyStateTitle() -> String {
        "No devices"
    }

    static func emptyStateMessage(autoFindHosts: Bool) -> String {
        if autoFindHosts {
            return "Auto Scan is running. Tap + to add one manually if your device does not appear."
        }
        return "Auto Scan is off. Tap + to add a device manually."
    }

    static func hostsAccessibilityValue(
        hostCount: Int,
        autoFindHosts: Bool,
        hostStateLabel: String,
        pairingStateLabel: String
    ) -> String {
        let autoScanLabel = autoFindHosts ? hostStateLabel : "Disabled"
        return "\(hostCount) host(s). Auto Scan \(autoScanLabel). Pairing \(pairingStateLabel)."
    }
}
