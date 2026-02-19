import Foundation

enum ShadowClientRTSPProtocolProfile {
    static let rtspSchemePrefix = "rtsp://"
    static let rtspsSchemePrefix = "rtsps://"

    static let defaultPort = 554
    static let fallbackVideoPayloadType = 96
    static let clientPortBase: UInt16 = 50_000
    static let clientPortProbeCount = 16
    static let interleavedFrameMagicByte: UInt8 = 0x24
    static let interleavedHeaderLength = 4
    static let rtpMinimumHeaderLength = 12
    static let rtpVersion = 2
    static let rtpVersionShift = 6
    static let rtpPaddingMask: UInt8 = 0x20
    static let rtpExtensionMask: UInt8 = 0x10
    static let rtpCSRCCountMask: UInt8 = 0x0F
    static let rtpMarkerMask: UInt8 = 0x80
    static let rtpPayloadTypeMask: UInt8 = 0x7F
    static let rtcpChannelParityRemainder = 1
    static let clockRateMarker = "/90000"
    static let av1ClockRateMarker = "av1\(clockRateMarker)"
    static let h265ClockRateMarker = "h265\(clockRateMarker)"
    static let hevcClockRateMarker = "hevc\(clockRateMarker)"
    static let hevcParameterSetMarker = "sprop-parameter-sets=AAAAAU"
    static let headerTerminatorCRLF = Data([0x0D, 0x0A, 0x0D, 0x0A])
    static let headerTerminatorLF = Data([0x0A, 0x0A])

    static let videoControlPaths = [
        "streamid=video/0/0",
        "streamid=video",
        "streamid=0",
    ]
    static let audioControlPaths = [
        "streamid=audio/0/0",
        "streamid=audio",
    ]
    static let controlStreamPaths = [
        "streamid=control/13/0",
        "streamid=control/1/0",
        "streamid=control",
    ]
    static let announcePaths = [
        "streamid=control/13/0",
        "streamid=video",
        "streamid=video/0/0",
    ]
    static let playPaths = [
        "/",
        "streamid=video",
        "streamid=audio",
    ]

    static let setupTransportHeaderPrefix = "unicast;X-GS-ClientPort="

    static func setupTransportHeader(clientPortBase: UInt16) -> String {
        "\(setupTransportHeaderPrefix)\(clientPortBase)-\(clientPortBase + 1)"
    }

    static func hostHeaderValue(forRTSPURLString urlString: String) -> String? {
        guard let components = URLComponents(string: urlString),
              let host = components.host
        else {
            return nil
        }

        let normalizedHost: String
        if host.contains(":"),
           !host.hasPrefix("["),
           !host.hasSuffix("]")
        {
            normalizedHost = "[\(host)]"
        } else {
            normalizedHost = host
        }

        guard let port = components.port else {
            return normalizedHost
        }

        return "\(normalizedHost):\(port)"
    }

    static func hasAbsoluteRTSPScheme(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix(rtspSchemePrefix) || lowered.hasPrefix(rtspsSchemePrefix)
    }

    static func withRTSPSchemeIfMissing(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return value
        }
        return trimmed.contains("://") ? trimmed : rtspSchemePrefix + trimmed
    }

    static func withHTTPSchemeIfMissing(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return value
        }
        return trimmed.contains("://") ? trimmed : ShadowClientGameStreamNetworkDefaults.httpSchemePrefix + trimmed
    }

    static func absolutePath(_ path: String) -> String {
        path.hasPrefix("/") ? path : "/" + path
    }
}
