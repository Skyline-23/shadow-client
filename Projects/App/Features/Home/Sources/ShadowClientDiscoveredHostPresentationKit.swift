import Foundation

struct ShadowClientDiscoveredHostPresentationKit {
    static func detailText(_ host: ShadowClientDiscoveredHost) -> String {
        "\(host.host):\(host.port) · \(host.serviceType)"
    }

    static func useButtonTitle() -> String {
        "Use"
    }

    static func connectButtonTitle() -> String {
        "Connect"
    }
}
