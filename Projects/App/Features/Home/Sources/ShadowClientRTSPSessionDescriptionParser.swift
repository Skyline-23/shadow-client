import Foundation

public enum ShadowClientVideoCodec: String, Equatable, Sendable {
    case h264
    case h265
}

public struct ShadowClientRTSPVideoTrackDescriptor: Equatable, Sendable {
    public let codec: ShadowClientVideoCodec
    public let rtpPayloadType: Int
    public let controlURL: String
    public let parameterSets: [Data]

    public init(
        codec: ShadowClientVideoCodec,
        rtpPayloadType: Int,
        controlURL: String,
        parameterSets: [Data]
    ) {
        self.codec = codec
        self.rtpPayloadType = rtpPayloadType
        self.controlURL = controlURL
        self.parameterSets = parameterSets
    }
}

public enum ShadowClientRTSPSessionDescriptionError: Error, Equatable, Sendable {
    case missingVideoTrack
    case missingControlURL
    case unsupportedCodec(String)
    case missingPayloadType
}

extension ShadowClientRTSPSessionDescriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingVideoTrack:
            return "RTSP SDP did not include a supported video track."
        case .missingControlURL:
            return "RTSP SDP did not provide a control URL."
        case let .unsupportedCodec(codec):
            return "RTSP video codec is unsupported: \(codec)"
        case .missingPayloadType:
            return "RTSP SDP video payload type is missing."
        }
    }
}

public enum ShadowClientRTSPSessionDescriptionParser {
    public static func parseVideoTrack(
        sdp: String,
        contentBase: String?,
        fallbackSessionURL: String
    ) throws -> ShadowClientRTSPVideoTrackDescriptor {
        let normalizedLines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var insideVideoSection = false
        var payloadType: Int?
        var controlValue: String?
        var codecByPayloadType: [Int: ShadowClientVideoCodec] = [:]
        var fmtpByPayloadType: [Int: [String: String]] = [:]

        for line in normalizedLines {
            if line.hasPrefix("m=") {
                insideVideoSection = line.hasPrefix("m=video")
                if insideVideoSection {
                    payloadType = parsePayloadType(fromMediaLine: line)
                }
                continue
            }

            guard insideVideoSection else {
                continue
            }

            if line.hasPrefix("a=control:") {
                controlValue = String(line.dropFirst("a=control:".count))
                continue
            }

            if line.hasPrefix("a=rtpmap:"),
               let mapping = parseRTPMap(line)
            {
                codecByPayloadType[mapping.payloadType] = mapping.codec
                continue
            }

            if line.hasPrefix("a=fmtp:"),
               let parsed = parseFMTP(line)
            {
                fmtpByPayloadType[parsed.payloadType] = parsed.parameters
                continue
            }
        }

        guard let payloadType else {
            throw ShadowClientRTSPSessionDescriptionError.missingPayloadType
        }
        guard let codec = codecByPayloadType[payloadType] else {
            throw ShadowClientRTSPSessionDescriptionError.missingVideoTrack
        }

        let resolvedControlURL = try resolveControlURL(
            controlValue,
            contentBase: contentBase,
            fallbackSessionURL: fallbackSessionURL
        )
        let parameters = fmtpByPayloadType[payloadType] ?? [:]

        return ShadowClientRTSPVideoTrackDescriptor(
            codec: codec,
            rtpPayloadType: payloadType,
            controlURL: resolvedControlURL,
            parameterSets: parameterSets(for: codec, from: parameters)
        )
    }

    public static func parseAudioControlURLs(
        sdp: String,
        contentBase: String?,
        fallbackSessionURL: String
    ) throws -> [String] {
        let lines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var insideAudioSection = false
        var controls: [String] = []
        for line in lines {
            if line.hasPrefix("m=") {
                insideAudioSection = line.hasPrefix("m=audio")
                continue
            }
            guard insideAudioSection else {
                continue
            }
            if line.hasPrefix("a=control:") {
                controls.append(String(line.dropFirst("a=control:".count)))
            }
        }

        var resolved: [String] = []
        for control in controls {
            let url = try resolveControlURL(
                control,
                contentBase: contentBase,
                fallbackSessionURL: fallbackSessionURL
            )
            if !resolved.contains(url) {
                resolved.append(url)
            }
        }
        return resolved
    }

    private static func parsePayloadType(fromMediaLine line: String) -> Int? {
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else {
            return nil
        }

        for token in parts.dropFirst(3) {
            if let value = Int(token) {
                return value
            }
        }
        return nil
    }

    private static func parseRTPMap(_ line: String) -> (payloadType: Int, codec: ShadowClientVideoCodec)? {
        let body = String(line.dropFirst("a=rtpmap:".count))
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let payloadType = Int(parts[0]) else {
            return nil
        }

        let codecName = parts[1].split(separator: "/").first.map(String.init)?.lowercased() ?? ""
        switch codecName {
        case "h264":
            return (payloadType, .h264)
        case "h265", "hevc":
            return (payloadType, .h265)
        default:
            return nil
        }
    }

    private static func parseFMTP(_ line: String) -> (payloadType: Int, parameters: [String: String])? {
        let body = String(line.dropFirst("a=fmtp:".count))
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let payloadType = Int(parts[0]) else {
            return nil
        }

        var values: [String: String] = [:]
        for rawPair in parts[1].split(separator: ";") {
            let pair = rawPair.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pair.isEmpty else {
                continue
            }
            let split = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if split.count == 2 {
                values[split[0].lowercased()] = split[1]
            } else {
                values[split[0].lowercased()] = ""
            }
        }
        return (payloadType, values)
    }

    private static func parameterSets(
        for codec: ShadowClientVideoCodec,
        from fmtp: [String: String]
    ) -> [Data] {
        switch codec {
        case .h264:
            guard let value = fmtp["sprop-parameter-sets"] else {
                return []
            }
            return value
                .split(separator: ",")
                .compactMap { Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .h265:
            let keys = ["sprop-vps", "sprop-sps", "sprop-pps"]
            return keys.compactMap { key in
                guard let value = fmtp[key] else {
                    return nil
                }
                return Data(base64Encoded: value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private static func resolveControlURL(
        _ controlValue: String?,
        contentBase: String?,
        fallbackSessionURL: String
    ) throws -> String {
        let trimmedControl = controlValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmedControl.hasPrefix("rtsp://") || trimmedControl.hasPrefix("rtsps://") {
            return trimmedControl
        }

        if let base = normalizedBase(contentBase) {
            if trimmedControl.isEmpty || trimmedControl == "*" {
                return base
            }
            return appendControlPath(trimmedControl, toBase: base)
        }

        guard let fallback = normalizedBase(fallbackSessionURL) else {
            throw ShadowClientRTSPSessionDescriptionError.missingControlURL
        }
        if trimmedControl.isEmpty || trimmedControl == "*" {
            return fallback
        }
        return appendControlPath(trimmedControl, toBase: fallback)
    }

    private static func normalizedBase(_ raw: String?) -> String? {
        guard let raw else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func appendControlPath(_ controlPath: String, toBase base: String) -> String {
        if controlPath.hasPrefix("/") {
            guard let baseURL = URL(string: base),
                  var components = URLComponents(
                    url: baseURL,
                    resolvingAgainstBaseURL: false
                  )
            else {
                return base + controlPath
            }
            components.path = controlPath
            return components.string ?? (base + controlPath)
        }

        if base.hasSuffix("/") {
            return base + controlPath
        }
        return base + "/" + controlPath
    }
}
