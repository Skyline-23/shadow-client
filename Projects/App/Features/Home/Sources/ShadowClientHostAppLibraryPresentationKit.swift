import Foundation

struct ShadowClientHostAppLibraryPresentationKit {
    static func primaryActionHint(hostTitle: String, canConnect: Bool) -> String {
        if canConnect {
            return "Connects to \(hostTitle) and opens the preferred remote session"
        }
        return "Disabled until \(hostTitle) is ready"
    }

    static func sectionTitle() -> String {
        "App Library"
    }

    static func lockedCallout() -> ShadowClientHostSpotlightCallout {
        .init(
            title: "Locked",
            message: "Pair this device first to load desktop or game apps.",
            tone: .warning
        )
    }

    static func emptyCallout() -> ShadowClientHostSpotlightCallout {
        .init(
            title: "No Apps Yet",
            message: "Refresh after the host session becomes ready.",
            tone: .info
        )
    }

    static func metadata(appID: Int, hdrSupported: Bool) -> String {
        let hdrLabel = hdrSupported ? "Y" : "N"
        return "App ID: \(appID) · HDR: \(hdrLabel)"
    }

    static func launchAccessibilityHint() -> String {
        "Launches the selected remote app and enters remote session view"
    }
}
