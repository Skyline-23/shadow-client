import Foundation

public enum ShadowClientVideoCodec: String, Codable, Equatable, Sendable {
    case h264
    case h265
    case av1
}

public struct ShadowClientRTSPVideoTrackDescriptor: Equatable, Sendable {
    public let codec: ShadowClientVideoCodec
    public let rtpPayloadType: Int
    public let candidateRTPPayloadTypes: [Int]
    public let controlURL: String
    public let parameterSets: [Data]

    public init(
        codec: ShadowClientVideoCodec,
        rtpPayloadType: Int,
        candidateRTPPayloadTypes: [Int] = [],
        controlURL: String,
        parameterSets: [Data]
    ) {
        self.codec = codec
        self.rtpPayloadType = rtpPayloadType
        var normalizedCandidates: [Int] = []

        func appendCandidate(_ payloadType: Int) {
            guard (0 ... 127).contains(payloadType),
                  payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType
            else {
                return
            }
            if !normalizedCandidates.contains(payloadType) {
                normalizedCandidates.append(payloadType)
            }
        }

        candidateRTPPayloadTypes.forEach(appendCandidate)
        appendCandidate(rtpPayloadType)
        if normalizedCandidates.isEmpty {
            normalizedCandidates = [rtpPayloadType]
        }
        self.candidateRTPPayloadTypes = normalizedCandidates
        self.controlURL = controlURL
        self.parameterSets = parameterSets
    }
}

public enum ShadowClientAudioCodec: Equatable, Sendable {
    case opus
    case pcmu
    case pcma
    case l16
    case unknown(String)

    public var label: String {
        switch self {
        case .opus:
            return "opus"
        case .pcmu:
            return "pcmu"
        case .pcma:
            return "pcma"
        case .l16:
            return "l16"
        case let .unknown(value):
            return value
        }
    }
}

public struct ShadowClientRTSPAudioTrackDescriptor: Equatable, Sendable {
    public let codec: ShadowClientAudioCodec
    public let rtpPayloadType: Int
    public let sampleRate: Int
    public let channelCount: Int
    public let controlURL: String?
    public let formatParameters: [String: String]

    public init(
        codec: ShadowClientAudioCodec,
        rtpPayloadType: Int,
        sampleRate: Int,
        channelCount: Int,
        controlURL: String?,
        formatParameters: [String: String]
    ) {
        self.codec = codec
        self.rtpPayloadType = rtpPayloadType
        self.sampleRate = max(8_000, sampleRate)
        self.channelCount = max(1, min(8, channelCount))
        self.controlURL = controlURL
        self.formatParameters = formatParameters
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
        var advertisedPayloadTypes: [Int] = []
        var controlValue: String?
        var codecByPayloadType: [Int: ShadowClientVideoCodec] = [:]
        var fmtpByPayloadType: [Int: [String: String]] = [:]
        var globalCodecByPayloadType: [Int: ShadowClientVideoCodec] = [:]
        var globalFmtpByPayloadType: [Int: [String: String]] = [:]
        let hostVideoHint = parseHostVideoHint(from: normalizedLines)

        for line in normalizedLines {
            if line.hasPrefix("m=") {
                insideVideoSection = line.hasPrefix("m=video")
                if insideVideoSection {
                    advertisedPayloadTypes = parsePayloadTypes(fromMediaLine: line)
                }
                continue
            }

            if let rtpMapLine = extractAttributeLine(line, prefix: "a=rtpmap:"),
               let mapping = parseRTPMap(rtpMapLine)
            {
                globalCodecByPayloadType[mapping.payloadType] = mapping.codec
            }

            if let fmtpLine = extractAttributeLine(line, prefix: "a=fmtp:"),
               let parsed = parseFMTP(fmtpLine)
            {
                globalFmtpByPayloadType[parsed.payloadType] = parsed.parameters
            }

            guard insideVideoSection else {
                continue
            }

            if let controlLine = extractAttributeLine(line, prefix: "a=control:") {
                controlValue = String(controlLine.dropFirst("a=control:".count))
                continue
            }

            if let rtpMapLine = extractAttributeLine(line, prefix: "a=rtpmap:"),
               let mapping = parseRTPMap(rtpMapLine)
            {
                codecByPayloadType[mapping.payloadType] = mapping.codec
                continue
            }

            if let fmtpLine = extractAttributeLine(line, prefix: "a=fmtp:"),
               let parsed = parseFMTP(fmtpLine)
            {
                fmtpByPayloadType[parsed.payloadType] = parsed.parameters
                continue
            }
        }

        if codecByPayloadType.isEmpty {
            codecByPayloadType = globalCodecByPayloadType
        }
        if fmtpByPayloadType.isEmpty {
            fmtpByPayloadType = globalFmtpByPayloadType
        }

        if advertisedPayloadTypes.isEmpty {
            let discoveredPayloadTypes = Set(codecByPayloadType.keys)
                .union(fmtpByPayloadType.keys)
            advertisedPayloadTypes = discoveredPayloadTypes.sorted()
        }

        if advertisedPayloadTypes.isEmpty,
           let hintedPayloadType = hostVideoHint.payloadType
        {
            advertisedPayloadTypes = [hintedPayloadType]
        }

        if let hintedCodec = hostVideoHint.codec {
            let payloadType = hostVideoHint.payloadType ?? advertisedPayloadTypes.first ?? ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType
            if !advertisedPayloadTypes.contains(payloadType) {
                advertisedPayloadTypes.append(payloadType)
            }
            if codecByPayloadType[payloadType] != hintedCodec {
                codecByPayloadType[payloadType] = hintedCodec
            }
        }

        let payloadType = selectPayloadType(
            advertisedPayloadTypes: advertisedPayloadTypes,
            codecByPayloadType: codecByPayloadType,
            fmtpByPayloadType: fmtpByPayloadType
        ) ?? ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType
        guard let codec = inferCodec(
            for: payloadType,
            codecByPayloadType: codecByPayloadType,
            fmtpByPayloadType: fmtpByPayloadType
        ) else {
            throw ShadowClientRTSPSessionDescriptionError.missingVideoTrack
        }

        let resolvedControlURL = try resolveControlURL(
            controlValue,
            contentBase: contentBase,
            fallbackSessionURL: fallbackSessionURL
        )
        let parameters = fmtpByPayloadType[payloadType] ?? [:]
        let payloadTypeCandidates = normalizedVideoPayloadTypeCandidates(
            selectedPayloadType: payloadType,
            advertisedPayloadTypes: advertisedPayloadTypes,
            codecByPayloadType: codecByPayloadType,
            fmtpByPayloadType: fmtpByPayloadType
        )

        return ShadowClientRTSPVideoTrackDescriptor(
            codec: codec,
            rtpPayloadType: payloadType,
            candidateRTPPayloadTypes: payloadTypeCandidates,
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

    public static func parseAudioTrack(
        sdp: String,
        contentBase: String?,
        fallbackSessionURL: String,
        preferredOpusChannelCount: Int? = nil
    ) -> ShadowClientRTSPAudioTrackDescriptor? {
        let lines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var insideAudioSection = false
        var discoveredAudioMediaSection = false
        var advertisedPayloadTypes: [Int] = []
        var controlValue: String?
        var codecByPayloadType: [Int: ShadowClientAudioCodec] = [:]
        var sampleRateByPayloadType: [Int: Int] = [:]
        var channelsByPayloadType: [Int: Int] = [:]
        var fmtpByPayloadType: [Int: [String: String]] = [:]

        for line in lines {
            if line.hasPrefix("m=") {
                insideAudioSection = line.hasPrefix("m=audio")
                if insideAudioSection {
                    discoveredAudioMediaSection = true
                    advertisedPayloadTypes = parsePayloadTypes(fromMediaLine: line)
                }
                continue
            }

            let parseGlobalAudioFallback = !discoveredAudioMediaSection
            guard insideAudioSection || parseGlobalAudioFallback else {
                continue
            }

            if let controlLine = extractAttributeLine(line, prefix: "a=control:") {
                let candidate = String(controlLine.dropFirst("a=control:".count))
                if insideAudioSection || isLikelyAudioControlValue(candidate) {
                    controlValue = candidate
                }
                continue
            }

            if let rtpMapLine = extractAttributeLine(line, prefix: "a=rtpmap:"),
               let mapping = parseAudioRTPMap(rtpMapLine)
            {
                guard insideAudioSection || shouldAcceptGlobalAudioRTPMap(mapping) else {
                    continue
                }
                codecByPayloadType[mapping.payloadType] = mapping.codec
                sampleRateByPayloadType[mapping.payloadType] = mapping.sampleRate
                channelsByPayloadType[mapping.payloadType] = mapping.channelCount
                continue
            }

            if let fmtpLine = extractAttributeLine(line, prefix: "a=fmtp:"),
               let parsed = parseFMTP(fmtpLine)
            {
                guard insideAudioSection || shouldAcceptGlobalAudioFMTP(
                    parsed,
                    knownAudioPayloadTypes: Set(codecByPayloadType.keys)
                ) else {
                    continue
                }
                let mergedParameters = mergeAudioFormatParameters(
                    existing: fmtpByPayloadType[parsed.payloadType],
                    new: parsed.parameters,
                    preferredOpusChannelCount: preferredOpusChannelCount
                )
                fmtpByPayloadType[parsed.payloadType] = mergedParameters
                continue
            }
        }

        if advertisedPayloadTypes.isEmpty {
            let discovered = Set(codecByPayloadType.keys)
                .union(fmtpByPayloadType.keys)
            advertisedPayloadTypes = discovered.sorted()
        }

        var candidates = advertisedPayloadTypes
        for payloadType in codecByPayloadType.keys.sorted() where !candidates.contains(payloadType) {
            candidates.append(payloadType)
        }

        guard let payloadType = candidates.first else {
            return nil
        }
        let selectedPayloadType = candidates.first(where: {
            codecByPayloadType[$0] == .opus
        }) ?? payloadType

        let codec: ShadowClientAudioCodec
        if let mappedCodec = codecByPayloadType[selectedPayloadType] {
            codec = mappedCodec
        } else if selectedPayloadType == ShadowClientMoonlightProtocolPolicy.Audio.primaryPayloadType ||
            fmtpByPayloadType[selectedPayloadType]?["surround-params"] != nil
        {
            // Sunshine commonly advertises audio PT=97 with surround-params while omitting rtpmap.
            codec = .opus
        } else {
            codec = .unknown("payload-\(selectedPayloadType)")
        }
        let sampleRate = sampleRateByPayloadType[selectedPayloadType] ?? 48_000
        let formatParameters = fmtpByPayloadType[selectedPayloadType] ?? [:]
        let mappedChannelCount = channelsByPayloadType[selectedPayloadType] ?? 2
        let channelCount: Int
        if codec == .opus,
           let surroundParams = formatParameters["surround-params"],
           let inferredChannelCount = inferOpusChannelCount(
               fromSurroundParams: surroundParams
           )
        {
            channelCount = inferredChannelCount
        } else {
            channelCount = mappedChannelCount
        }
        let resolvedControlURL: String?
        if let controlValue {
            resolvedControlURL = try? resolveControlURL(
                controlValue,
                contentBase: contentBase,
                fallbackSessionURL: fallbackSessionURL
            )
        } else {
            resolvedControlURL = nil
        }

        return ShadowClientRTSPAudioTrackDescriptor(
            codec: codec,
            rtpPayloadType: selectedPayloadType,
            sampleRate: sampleRate,
            channelCount: channelCount,
            controlURL: resolvedControlURL,
            formatParameters: formatParameters
        )
    }

    static func inferFallbackVideoPayloadType(
        sdp: String,
        preferredCodec: ShadowClientVideoCodec?
    ) -> Int? {
        let lines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var advertisedPayloadTypes: [Int] = []
        var codecByPayloadType: [Int: ShadowClientVideoCodec] = [:]
        var fmtpByPayloadType: [Int: [String: String]] = [:]

        for line in lines {
            if line.hasPrefix("m=video") {
                for payloadType in parsePayloadTypes(fromMediaLine: line) where !advertisedPayloadTypes.contains(payloadType) {
                    advertisedPayloadTypes.append(payloadType)
                }
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

        var candidates: [Int] = []

        func appendCandidate(_ payloadType: Int) {
            if !candidates.contains(payloadType) {
                candidates.append(payloadType)
            }
        }

        for payloadType in advertisedPayloadTypes {
            appendCandidate(payloadType)
        }
        for payloadType in codecByPayloadType.keys.sorted() {
            appendCandidate(payloadType)
        }
        for payloadType in fmtpByPayloadType.keys.sorted() {
            appendCandidate(payloadType)
        }

        if let preferredCodec {
            for candidate in candidates {
                if inferCodec(
                    for: candidate,
                    codecByPayloadType: codecByPayloadType,
                    fmtpByPayloadType: fmtpByPayloadType
                ) == preferredCodec {
                    return candidate
                }
            }
        }

        return selectPayloadType(
            advertisedPayloadTypes: advertisedPayloadTypes,
            codecByPayloadType: codecByPayloadType,
            fmtpByPayloadType: fmtpByPayloadType
        )
    }

    private static func parsePayloadTypes(fromMediaLine line: String) -> [Int] {
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else {
            return []
        }

        var payloadTypes: [Int] = []
        for token in parts.dropFirst(3) {
            if let value = Int(token), !payloadTypes.contains(value) {
                payloadTypes.append(value)
            }
        }
        return payloadTypes
    }

    private static func normalizedVideoPayloadTypeCandidates(
        selectedPayloadType: Int,
        advertisedPayloadTypes: [Int],
        codecByPayloadType: [Int: ShadowClientVideoCodec],
        fmtpByPayloadType: [Int: [String: String]]
    ) -> [Int] {
        var candidates: [Int] = []

        func append(_ payloadType: Int) {
            guard (0 ... 127).contains(payloadType),
                  payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType
            else {
                return
            }
            if !candidates.contains(payloadType) {
                candidates.append(payloadType)
            }
        }

        append(selectedPayloadType)
        for payloadType in advertisedPayloadTypes {
            append(payloadType)
        }
        for payloadType in codecByPayloadType.keys.sorted() {
            append(payloadType)
        }
        for payloadType in fmtpByPayloadType.keys.sorted() {
            append(payloadType)
        }
        return candidates
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
        case "av1":
            return (payloadType, .av1)
        default:
            return nil
        }
    }

    private static func parseAudioRTPMap(
        _ line: String
    ) -> (payloadType: Int, codec: ShadowClientAudioCodec, sampleRate: Int, channelCount: Int)? {
        let body = String(line.dropFirst("a=rtpmap:".count))
        let parts = body.split(separator: " ", maxSplits: 1).map(String.init)
        guard parts.count == 2, let payloadType = Int(parts[0]) else {
            return nil
        }

        let codecComponents = parts[1]
            .split(separator: "/")
            .map { String($0).lowercased() }
        guard let codecName = codecComponents.first else {
            return nil
        }

        let sampleRate = Int(codecComponents.dropFirst().first ?? "") ?? 48_000
        let channelCount = Int(codecComponents.dropFirst(2).first ?? "") ?? 2

        let codec: ShadowClientAudioCodec
        switch codecName {
        case "opus":
            codec = .opus
        case "pcmu", "g711u", "ulaw", "mu-law":
            codec = .pcmu
        case "pcma", "g711a", "alaw", "a-law":
            codec = .pcma
        case "l16", "pcm":
            codec = .l16
        default:
            codec = .unknown(codecName)
        }

        return (payloadType, codec, sampleRate, channelCount)
    }

    private static func parseHostVideoHint(
        from lines: [String]
    ) -> (payloadType: Int?, codec: ShadowClientVideoCodec?) {
        var payloadType: Int?
        var codec: ShadowClientVideoCodec?

        for line in lines {
            let lower = line.lowercased()

            if let value = extractColonSeparatedValue(
                line: line,
                key: "a=x-nv-video[0].payloadtype:"
            ), let parsed = Int(value) {
                payloadType = parsed
            }

            if let value = extractColonSeparatedValue(
                line: line,
                key: "a=x-nv-vqos[0].bitstreamformat:"
            ), let parsed = Int(value) {
                switch parsed {
                case 0:
                    codec = .h264
                case 1:
                    codec = .h265
                case 2:
                    codec = .av1
                default:
                    break
                }
            }

            if codec == nil, lower.contains("sprop-parameter-sets=aaaau") {
                codec = .h265
            }
        }

        return (payloadType, codec)
    }

    private static func extractColonSeparatedValue(
        line: String,
        key: String
    ) -> String? {
        let lower = line.lowercased()
        guard lower.hasPrefix(key.lowercased()) else {
            return nil
        }
        return String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespacesAndNewlines)
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

    private static func inferOpusChannelCount(
        fromSurroundParams rawValue: String
    ) -> Int? {
        let firstToken = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0 == " " })
            .first
            .map(String.init) ?? ""
        guard let firstCharacter = firstToken.first,
              let channelCount = Int(String(firstCharacter))
        else {
            return nil
        }

        switch channelCount {
        case 2, 6, 8:
            return channelCount
        default:
            return nil
        }
    }

    private static func isLikelyAudioControlValue(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }
        return normalized.contains("audio")
    }

    private static func shouldAcceptGlobalAudioRTPMap(
        _ mapping: (payloadType: Int, codec: ShadowClientAudioCodec, sampleRate: Int, channelCount: Int)
    ) -> Bool {
        if isKnownAudioCodec(mapping.codec) {
            return true
        }
        // Sunshine frequently omits full audio media descriptors but still uses PT97 Opus.
        return mapping.payloadType == ShadowClientMoonlightProtocolPolicy.Audio.primaryPayloadType
    }

    private static func shouldAcceptGlobalAudioFMTP(
        _ parsed: (payloadType: Int, parameters: [String: String]),
        knownAudioPayloadTypes: Set<Int>
    ) -> Bool {
        if knownAudioPayloadTypes.contains(parsed.payloadType) {
            return true
        }
        if parsed.payloadType == ShadowClientMoonlightProtocolPolicy.Audio.primaryPayloadType {
            return true
        }
        return parsed.parameters.keys.contains { key in
            switch key {
            case "surround-params", "sprop-stereo", "maxplaybackrate":
                return true
            default:
                return false
            }
        }
    }

    private static func mergeAudioFormatParameters(
        existing: [String: String]?,
        new: [String: String],
        preferredOpusChannelCount: Int?
    ) -> [String: String] {
        var merged = existing ?? [:]
        for (key, value) in new {
            if key == "surround-params",
               let current = merged[key]
            {
                merged[key] = preferredSurroundParams(
                    current: current,
                    candidate: value,
                    preferredOpusChannelCount: preferredOpusChannelCount
                )
            } else {
                merged[key] = value
            }
        }
        return merged
    }

    private static func preferredSurroundParams(
        current: String,
        candidate: String,
        preferredOpusChannelCount: Int?
    ) -> String {
        let currentChannels = inferOpusChannelCount(fromSurroundParams: current) ?? 0
        let candidateChannels = inferOpusChannelCount(fromSurroundParams: candidate) ?? 0
        guard let preferredOpusChannelCount else {
            return candidateChannels >= currentChannels ? candidate : current
        }

        let currentDistance = abs(currentChannels - preferredOpusChannelCount)
        let candidateDistance = abs(candidateChannels - preferredOpusChannelCount)

        if candidateDistance < currentDistance {
            return candidate
        }
        if candidateDistance > currentDistance {
            return current
        }
        if candidateChannels == preferredOpusChannelCount {
            return candidate
        }
        if currentChannels == preferredOpusChannelCount {
            return current
        }
        if candidateChannels == currentChannels {
            return candidate
        }
        return candidateChannels < currentChannels ? candidate : current
    }

    private static func isKnownAudioCodec(_ codec: ShadowClientAudioCodec) -> Bool {
        switch codec {
        case .opus, .pcmu, .pcma, .l16:
            return true
        case .unknown:
            return false
        }
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
                .compactMap { decodeBase64Relaxed($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .h265:
            let keys = ["sprop-vps", "sprop-sps", "sprop-pps"]
            let splitParameterSets: [Data] = keys.compactMap { key in
                guard let value = fmtp[key] else {
                    return nil
                }
                return decodeBase64Relaxed(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if !splitParameterSets.isEmpty {
                return splitParameterSets
            }
            guard let value = fmtp["sprop-parameter-sets"] else {
                return []
            }
            return value
                .split(separator: ",")
                .compactMap { decodeBase64Relaxed($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        case .av1:
            let keys = ["config", "sprop-parameter-sets"]
            var records: [Data] = []
            for key in keys {
                guard let value = fmtp[key] else {
                    continue
                }
                for token in value.split(separator: ",") {
                    guard let record = decodeBase64Relaxed(
                        token.trimmingCharacters(in: .whitespacesAndNewlines)
                    ) else {
                        continue
                    }
                    records.append(record)
                }
            }
            return records
        }
    }

    private static func decodeBase64Relaxed(_ value: String) -> Data? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if let direct = Data(base64Encoded: trimmed) {
            return direct
        }

        let remainder = trimmed.count % 4
        guard remainder != 0 else {
            return nil
        }
        let padded = trimmed + String(repeating: "=", count: 4 - remainder)
        return Data(base64Encoded: padded)
    }

    private static func selectPayloadType(
        advertisedPayloadTypes: [Int],
        codecByPayloadType: [Int: ShadowClientVideoCodec],
        fmtpByPayloadType: [Int: [String: String]]
    ) -> Int? {
        var candidates: [Int] = []
        candidates.append(contentsOf: advertisedPayloadTypes)
        candidates.append(contentsOf: codecByPayloadType.keys.sorted())
        candidates.append(contentsOf: fmtpByPayloadType.keys.sorted())

        for candidate in candidates {
            if inferCodec(
                for: candidate,
                codecByPayloadType: codecByPayloadType,
                fmtpByPayloadType: fmtpByPayloadType
            ) != nil {
                return candidate
            }
        }
        return candidates.first
    }

    private static func inferCodec(
        for payloadType: Int,
        codecByPayloadType: [Int: ShadowClientVideoCodec],
        fmtpByPayloadType: [Int: [String: String]]
    ) -> ShadowClientVideoCodec? {
        if let mapped = codecByPayloadType[payloadType] {
            return mapped
        }

        let fmtp = fmtpByPayloadType[payloadType] ?? [:]
        if fmtp["sprop-vps"] != nil {
            return .h265
        }
        if fmtp["sprop-parameter-sets"] != nil {
            return .h264
        }
        if fmtp["profile"] != nil || fmtp["level-idx"] != nil {
            return .av1
        }
        return nil
    }

    private static func resolveControlURL(
        _ controlValue: String?,
        contentBase: String?,
        fallbackSessionURL: String
    ) throws -> String {
        let trimmedControl = controlValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ShadowClientRTSPProtocolProfile.hasAbsoluteRTSPScheme(trimmedControl) {
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

    private static func extractAttributeLine(_ line: String, prefix: String) -> String? {
        let lower = line.lowercased()
        guard let range = lower.range(of: prefix.lowercased()) else {
            return nil
        }
        return String(line[range.lowerBound...])
    }
}
