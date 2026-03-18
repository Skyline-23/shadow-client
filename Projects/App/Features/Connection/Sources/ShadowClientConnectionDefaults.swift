import Foundation

public enum ShadowClientGameStreamNetworkDefaults {
    public static let httpScheme = "http"
    public static let httpsScheme = "https"
    public static let httpSchemePrefix = "\(httpScheme)://"

    public static let defaultHTTPPort = 47_989
    public static let defaultHTTPSPort = 47_984
    public static let httpHTTPSPortOffset = defaultHTTPPort - defaultHTTPSPort
    public static let defaultServicePorts: [Int] = [
        defaultHTTPSPort,
        defaultHTTPPort,
        48_010,
    ]

    public static let defaultRequestTimeout: TimeInterval = 8
    public static let pairingPINEntryTimeout: TimeInterval = 45
    public static let pairingStageTimeout: TimeInterval = 15
    public static let defaultSessionConnectTimeout: Duration = .seconds(10)

    public static let minimumPort = 1
    public static let maximumPort = Int(UInt16.max)

    public static func httpPort(forHTTPSPort httpsPort: Int) -> Int {
        httpsPort + httpHTTPSPortOffset
    }

    public static func httpsPort(forHTTPPort httpPort: Int) -> Int {
        httpPort - httpHTTPSPortOffset
    }

    public static func canonicalHTTPSPort(fromCandidatePort port: Int) -> Int {
        guard isLikelyHTTPPort(port) else {
            return port
        }
        let httpsPort = httpsPort(forHTTPPort: port)
        guard (minimumPort...maximumPort).contains(httpsPort) else {
            return port
        }
        return httpsPort
    }

    public static func isLikelyHTTPPort(_ port: Int) -> Bool {
        guard (minimumPort...maximumPort).contains(port),
              port > httpHTTPSPortOffset
        else {
            return false
        }
        return port == defaultHTTPPort || port % 100 == defaultHTTPPort % 100
    }
}

public enum ShadowClientHostProbeDefaults {
    public static let tcpPortTimeout: Duration = .seconds(1)
}
