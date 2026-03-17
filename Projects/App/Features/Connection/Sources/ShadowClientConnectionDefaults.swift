import Foundation

public enum ShadowClientGameStreamNetworkDefaults {
    public static let httpScheme = "http"
    public static let httpsScheme = "https"
    public static let httpSchemePrefix = "\(httpScheme)://"

    public static let defaultHTTPPort = 47_989
    public static let defaultHTTPSPort = 47_984
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
    public static let httpsOffsetFromHTTPPort = defaultHTTPSPort - defaultHTTPPort
    public static let webUIOffsetFromHTTPPort = 1
    public static let rtspOffsetFromHTTPPort = 21
    public static let streamUDPRangeOffset = 9...11

    public static func mappedHTTPSPort(forHTTPPort httpPort: Int) -> Int? {
        guard (minimumPort...maximumPort).contains(httpPort) else {
            return nil
        }

        let candidate = httpPort + httpsOffsetFromHTTPPort
        guard (minimumPort...maximumPort).contains(candidate) else {
            return nil
        }
        return candidate
    }

    public static func mappedHTTPPort(forHTTPSPort httpsPort: Int) -> Int? {
        guard (minimumPort...maximumPort).contains(httpsPort) else {
            return nil
        }

        let candidate = httpsPort - httpsOffsetFromHTTPPort
        guard (minimumPort...maximumPort).contains(candidate) else {
            return nil
        }
        return candidate
    }
}

public enum ShadowClientHostProbeDefaults {
    public static let tcpPortTimeout: Duration = .seconds(1)
}
