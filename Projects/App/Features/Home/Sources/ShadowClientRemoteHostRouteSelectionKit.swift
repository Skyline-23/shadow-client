import Foundation
import ShadowClientFeatureConnection

enum ShadowClientRemoteHostRouteSelectionKit {
    static func displayCandidate(
        for host: ShadowClientRemoteHostDescriptor,
        allHosts: [ShadowClientRemoteHostDescriptor]
    ) -> String {
        let endpoint = host.routes.manual ?? host.routes.remote ?? host.routes.active
        let normalizedHost = endpoint.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let distinctPortsForHost = Set(
            allHosts
                .flatMap(\.routes.allEndpoints)
                .filter {
                    $0.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedHost
                }
                .map(\.httpsPort)
        )
        if endpoint.httpsPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
           distinctPortsForHost.count <= 1 {
            return endpoint.host
        }
        return "\(endpoint.host):\(endpoint.httpsPort)"
    }

    static func runtimeConnectCandidate(for host: ShadowClientRemoteHostDescriptor) -> String {
        let endpoint = host.routes.local ?? host.routes.active
        if endpoint.httpsPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort {
            return endpoint.host
        }
        return "\(endpoint.host):\(endpoint.httpsPort)"
    }
}
