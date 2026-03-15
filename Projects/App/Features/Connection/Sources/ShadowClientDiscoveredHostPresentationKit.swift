import Foundation

public struct ShadowClientDiscoveredHostPresentationKit {
    public static func detailText(_ host: ShadowClientDiscoveredHost) -> String {
        "\(host.host):\(host.port) · \(host.serviceType)"
    }

    public static func useButtonTitle() -> String {
        "Use"
    }

    public static func connectButtonTitle() -> String {
        "Connect"
    }
}
