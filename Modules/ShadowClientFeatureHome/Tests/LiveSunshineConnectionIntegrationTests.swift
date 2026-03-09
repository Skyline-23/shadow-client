import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#endif

@Test("Live Sunshine serverinfo and RTSP probe succeeds on wifi host")
func liveSunshineRTSPOptionsAndDescribeSucceeds() async throws {
    guard let config = LiveSunshineRTSPIntegrationConfiguration.enabledFromEnvironment() else {
        return
    }

    let serverInfo = await fetchServerInfo(config: config)
    #expect(serverInfo.statusCode == 200)
    #expect(!serverInfo.localIP.isEmpty)

    guard serverInfo.pairStatus == "1" else {
        // Live RTSP setup requires a paired identity context.
        return
    }

    let rtspHost = serverInfo.localIP

    let optionsRequest = """
    OPTIONS rtsp://\(rtspHost):\(config.rtspPort)/ RTSP/1.0\r
    CSeq: 1\r
    User-Agent: ShadowClientIntegrationTests/1.0\r
    \r
    """

    let optionsResponse = try sendRequestWithRetry(
        host: rtspHost,
        port: config.rtspPort,
        timeout: config.timeout,
        request: optionsRequest,
        attempts: config.retries
    )
    #expect(optionsResponse.statusCode == 200)

    let describeRequest = """
    DESCRIBE rtsp://\(rtspHost):\(config.rtspPort)/ RTSP/1.0\r
    CSeq: 2\r
    Accept: application/sdp\r
    User-Agent: ShadowClientIntegrationTests/1.0\r
    \r
    """

    let describeResponse = try sendRequestWithRetry(
        host: rtspHost,
        port: config.rtspPort,
        timeout: config.timeout,
        request: describeRequest,
        attempts: config.retries
    )
    #expect(describeResponse.statusCode == 200)

    let bodyText = String(decoding: describeResponse.body, as: UTF8.self)
    #expect(bodyText.contains("a=rtpmap:"))
    #expect(bodyText.localizedCaseInsensitiveContains("av1") || bodyText.localizedCaseInsensitiveContains("h264") || bodyText.localizedCaseInsensitiveContains("h265"))
}

private struct LiveSunshineRTSPIntegrationConfiguration: Sendable {
    let host: String
    let rtspPort: Int
    let externalHTTPPort: Int
    let timeout: TimeInterval
    let retries: Int

    static func enabledFromEnvironment() -> Self? {
        let environment = ProcessInfo.processInfo.environment
        guard boolFlag(environment["SHADOWCLIENT_LIVE_INTEGRATION"]) else {
            return nil
        }

        return .init(
            host: stringValue(environment["SHADOWCLIENT_LIVE_HOST"], fallback: "stream-host.example.invalid"),
            rtspPort: intValue(environment["SHADOWCLIENT_LIVE_RTSP_PORT"], fallback: 48010),
            externalHTTPPort: intValue(environment["SHADOWCLIENT_LIVE_HTTP_PORT"], fallback: 47989),
            timeout: doubleValue(environment["SHADOWCLIENT_LIVE_RTSP_TIMEOUT_SECONDS"], fallback: 4.0),
            retries: intValue(environment["SHADOWCLIENT_LIVE_RTSP_RETRIES"], fallback: 2)
        )
    }

    private static func boolFlag(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private static func stringValue(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func intValue(_ value: String?, fallback: Int) -> Int {
        guard
            let value,
            let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
            parsed > 0
        else {
            return fallback
        }
        return parsed
    }

    private static func doubleValue(_ value: String?, fallback: Double) -> Double {
        guard
            let value,
            let parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
            parsed > 0
        else {
            return fallback
        }
        return parsed
    }
}

private struct RTSPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

private struct LiveServerInfoProbeResult: Sendable {
    let statusCode: Int
    let localIP: String
    let pairStatus: String
}

private func fetchServerInfo(config: LiveSunshineRTSPIntegrationConfiguration) async -> LiveServerInfoProbeResult {
    guard var components = URLComponents(string: "http://\(config.host):\(config.externalHTTPPort)/serverinfo") else {
        return .init(statusCode: -1, localIP: "", pairStatus: "")
    }
    components.queryItems = [
        .init(name: "uniqueid", value: "0123456789ABCDEF"),
        .init(name: "uuid", value: UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()),
    ]
    guard let url = components.url else {
        return .init(statusCode: -1, localIP: "", pairStatus: "")
    }

    var request = URLRequest(url: url)
    request.timeoutInterval = config.timeout

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let xml = String(decoding: data, as: UTF8.self)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        let localIP = xml.value(forTag: "LocalIP")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let pairStatus = xml.value(forTag: "PairStatus")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .init(statusCode: statusCode, localIP: localIP, pairStatus: pairStatus)
    } catch {
        return .init(statusCode: -1, localIP: "", pairStatus: "")
    }
}

private enum RTSPProbeError: Error, LocalizedError {
    case invalidHost(String)
    case socketCreateFailed(errno: Int32)
    case connectFailed(errno: Int32)
    case writeFailed(errno: Int32)
    case readFailed(errno: Int32)
    case malformedResponse

    var errorDescription: String? {
        switch self {
        case let .invalidHost(host):
            return "Invalid host: \(host)"
        case let .socketCreateFailed(code):
            return "Socket create failed: errno=\(code)"
        case let .connectFailed(code):
            return "Socket connect failed: errno=\(code)"
        case let .writeFailed(code):
            return "Socket write failed: errno=\(code)"
        case let .readFailed(code):
            return "Socket read failed: errno=\(code)"
        case .malformedResponse:
            return "Malformed RTSP response"
        }
    }
}

private func sendRequestWithRetry(
    host: String,
    port: Int,
    timeout: TimeInterval,
    request: String,
    attempts: Int
) throws -> RTSPResponse {
    var lastError: Error?
    let maxAttempts = max(1, attempts)

    for _ in 0..<maxAttempts {
        do {
            return try sendRTSPRequest(
                host: host,
                port: port,
                timeout: timeout,
                request: request
            )
        } catch {
            lastError = error
        }
    }

    throw lastError ?? RTSPProbeError.malformedResponse
}

private func sendRTSPRequest(
    host: String,
    port: Int,
    timeout: TimeInterval,
    request: String
) throws -> RTSPResponse {
#if canImport(Darwin)
    let socketFD = try connectSocket(host: host, port: port, timeout: timeout)
    defer { close(socketFD) }

    try writeAll(socketFD: socketFD, data: Data(request.utf8))
    let responseData = try readResponse(socketFD: socketFD)
    return try parseRTSPResponse(data: responseData)
#else
    throw RTSPProbeError.invalidHost(host)
#endif
}

#if canImport(Darwin)
private func connectSocket(host: String, port: Int, timeout: TimeInterval) throws -> Int32 {
    var hints = addrinfo(
        ai_flags: AI_ADDRCONFIG,
        ai_family: AF_UNSPEC,
        ai_socktype: SOCK_STREAM,
        ai_protocol: IPPROTO_TCP,
        ai_addrlen: 0,
        ai_canonname: nil,
        ai_addr: nil,
        ai_next: nil
    )

    var result: UnsafeMutablePointer<addrinfo>?
    let status = getaddrinfo(host, String(port), &hints, &result)
    guard status == 0, let firstResult = result else {
        throw RTSPProbeError.invalidHost(host)
    }
    defer { freeaddrinfo(firstResult) }

    var pointer: UnsafeMutablePointer<addrinfo>? = firstResult
    while let info = pointer {
        let socketFD = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        if socketFD >= 0 {
            setSocketTimeout(socketFD: socketFD, timeout: timeout)

            if connect(socketFD, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 {
                return socketFD
            }

            close(socketFD)
        }
        pointer = info.pointee.ai_next
    }

    throw RTSPProbeError.connectFailed(errno: errno)
}

private func setSocketTimeout(socketFD: Int32, timeout: TimeInterval) {
    let seconds = max(1, Int(timeout))
    var timeoutValue = timeval(tv_sec: seconds, tv_usec: 0)
    withUnsafePointer(to: &timeoutValue) { pointer in
        _ = setsockopt(socketFD, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
    }
}

private func writeAll(socketFD: Int32, data: Data) throws {
    try data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return
        }

        var offset = 0
        while offset < data.count {
            let pointer = baseAddress.advanced(by: offset)
            let written = send(socketFD, pointer, data.count - offset, 0)
            if written <= 0 {
                throw RTSPProbeError.writeFailed(errno: errno)
            }
            offset += written
        }
    }
}

private func readResponse(socketFD: Int32) throws -> Data {
    var received = Data()
    var headerParsed = false
    var expectedBodyBytes = 0
    let headerDelimiter = Data("\r\n\r\n".utf8)

    while true {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let bytesRead = recv(socketFD, &buffer, buffer.count, 0)
        if bytesRead < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                break
            }
            throw RTSPProbeError.readFailed(errno: errno)
        }
        if bytesRead == 0 {
            break
        }

        received.append(buffer, count: bytesRead)

        if !headerParsed, let headerRange = received.range(of: headerDelimiter) {
            headerParsed = true
            let headerData = received[..<headerRange.lowerBound]
            let headerText = String(decoding: headerData, as: UTF8.self)
            expectedBodyBytes = contentLength(from: headerText) ?? 0
        }

        if headerParsed, let headerRange = received.range(of: headerDelimiter) {
            let bodyStart = headerRange.upperBound
            let bodyCount = received.count - bodyStart
            if bodyCount >= expectedBodyBytes {
                break
            }
        }
    }

    return received
}
#endif

private func parseRTSPResponse(data: Data) throws -> RTSPResponse {
    let delimiter = Data("\r\n\r\n".utf8)
    guard let headerRange = data.range(of: delimiter) else {
        throw RTSPProbeError.malformedResponse
    }

    let headerData = data[..<headerRange.lowerBound]
    let headerText = String(decoding: headerData, as: UTF8.self)
    var lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
    guard let statusLine = lines.first else {
        throw RTSPProbeError.malformedResponse
    }
    lines.removeFirst()

    let statusParts = statusLine.split(separator: " ")
    guard statusParts.count >= 2, let statusCode = Int(statusParts[1]) else {
        throw RTSPProbeError.malformedResponse
    }

    var headers: [String: String] = [:]
    for line in lines {
        guard let separator = line.firstIndex(of: ":") else { continue }
        let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        headers[name] = value
    }

    let bodyStart = headerRange.upperBound
    let declaredBodyLength = Int(headers["content-length"] ?? "") ?? 0
    let rawBody = data.suffix(from: bodyStart)
    let body = declaredBodyLength > 0 ? rawBody.prefix(declaredBodyLength) : rawBody

    return RTSPResponse(statusCode: statusCode, headers: headers, body: Data(body))
}

private func contentLength(from headerText: String) -> Int? {
    for line in headerText.split(separator: "\r\n", omittingEmptySubsequences: true) {
        guard let separator = line.firstIndex(of: ":") else { continue }
        let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard key == "content-length" else { continue }
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(value)
    }
    return nil
}

private extension String {
    func value(forTag tag: String) -> String? {
        guard
            let startRange = range(of: "<\(tag)>"),
            let endRange = range(of: "</\(tag)>", range: startRange.upperBound..<endIndex)
        else {
            return nil
        }
        return String(self[startRange.upperBound..<endRange.lowerBound])
    }
}
