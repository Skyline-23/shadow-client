import Foundation
import Network
import Testing
@testable import ShadowClientFeatureHome

@Test("HTTP transport maps pinned certificate mismatch into unauthorized response")
func httpTransportMapsPinnedCertificateMismatchIntoUnauthorizedResponse() {
    let error = ShadowClientGameStreamHTTPTransport.requestFailureError(
        URLError(.secureConnectionFailed),
        tlsFailure: .serverCertificateMismatch
    )

    #expect(error == .responseRejected(code: 401, message: "Server certificate mismatch"))
}

@Test("HTTP transport maps missing client certificate into certificate-required failure")
func httpTransportMapsMissingClientCertificateIntoCertificateRequiredFailure() {
    let error = ShadowClientGameStreamHTTPTransport.requestFailureError(
        URLError(.secureConnectionFailed),
        tlsFailure: .clientCertificateRequired
    )

    #expect(error == .requestFailed("TLSV1_ALERT_CERTIFICATE_REQUIRED: certificate required"))
}

@Test("HTTP transport fails ready waits immediately for refused or unreachable socket errors")
func httpTransportFailsReadyWaitImmediatelyForTerminalNWErrors() {
    #expect(
        ShadowClientGameStreamHTTPTransport.shouldFailConnectionReadyImmediately(
            NWError.posix(.ECONNREFUSED)
        )
    )
    #expect(
        ShadowClientGameStreamHTTPTransport.shouldFailConnectionReadyImmediately(
            NWError.posix(.ENETUNREACH)
        )
    )
}

@Test("HTTP transport keeps waiting on non-terminal ready-state errors")
func httpTransportKeepsWaitingOnNonTerminalReadyErrors() {
    #expect(
        !ShadowClientGameStreamHTTPTransport.shouldFailConnectionReadyImmediately(
            NWError.posix(.ETIMEDOUT)
        )
    )
    #expect(
        !ShadowClientGameStreamHTTPTransport.shouldFailConnectionReadyImmediately(
            URLError(.timedOut)
        )
    )
}

@Test("HTTP request builder includes method headers and body length")
func httpRequestBuilderIncludesMethodHeadersAndBodyLength() {
    let url = URL(string: "https://second-stream-host.local:47984/actions/clipboard?type=text")!
    let requestData = ShadowClientGameStreamHTTPTransport.makeHTTPRequestData(
        url: url,
        host: "second-stream-host.local",
        method: "POST",
        headers: [
            "Content-Type": "text/plain; charset=utf-8",
        ],
        body: Data("hello".utf8)
    )

    let requestText = String(decoding: requestData, as: UTF8.self)
    #expect(requestText.contains("POST /actions/clipboard?type=text HTTP/1.1"))
    #expect(requestText.contains("Host: second-stream-host.local:47984"))
    #expect(requestText.contains("Content-Type: text/plain; charset=utf-8"))
    #expect(requestText.contains("Content-Length: 5"))
    #expect(requestText.hasSuffix("\r\n\r\nhello"))
}

@Test("HTTP response metadata parser extracts status code and reason phrase")
func httpResponseMetadataParserExtractsStatusCodeAndReasonPhrase() throws {
    let response = Data(
        """
        HTTP/1.1 404 Not Found\r
        Content-Length: 2\r
        \r
        {}
        """.utf8
    )

    let metadata = try ShadowClientGameStreamHTTPTransport.parseHTTPResponseMetadata(
        from: response
    )

    #expect(
        metadata == .init(statusCode: 404, reasonPhrase: "Not Found")
    )
}

@Test("HTTP response metadata parser rejects malformed status lines")
func httpResponseMetadataParserRejectsMalformedStatusLines() {
    let response = Data(
        """
        not-http\r
        Content-Length: 0\r
        \r
        """.utf8
    )

    #expect(throws: ShadowClientGameStreamError.invalidResponse) {
        try ShadowClientGameStreamHTTPTransport.parseHTTPResponseMetadata(from: response)
    }
}

@Test("HTTP response completion accepts declared body lengths without waiting for stream end")
func httpResponseCompletionAcceptsDeclaredBodyLengthsWithoutWaitingForStreamEnd() {
    #expect(
        ShadowClientGameStreamHTTPTransport.isHTTPResponseComplete(
            bodyLength: 8,
            expectedResponseBodyLength: 8,
            reachedStreamEnd: false
        )
    )
    #expect(
        !ShadowClientGameStreamHTTPTransport.isHTTPResponseComplete(
            bodyLength: 7,
            expectedResponseBodyLength: 8,
            reachedStreamEnd: true
        )
    )
}

@Test("HTTP response completion accepts stream end when content length is absent")
func httpResponseCompletionAcceptsStreamEndWithoutContentLength() {
    #expect(
        ShadowClientGameStreamHTTPTransport.isHTTPResponseComplete(
            bodyLength: 0,
            expectedResponseBodyLength: nil,
            reachedStreamEnd: true
        )
    )
    #expect(
        !ShadowClientGameStreamHTTPTransport.isHTTPResponseComplete(
            bodyLength: 1024,
            expectedResponseBodyLength: nil,
            reachedStreamEnd: false
        )
    )
}

@Test("HTTP response failure helper rejects ended streams that never produced headers")
func httpResponseFailureHelperRejectsEndedStreamsWithoutHeaders() {
    #expect(
        ShadowClientGameStreamHTTPTransport.shouldFailEndedHTTPResponseBeforeHeaders(
            responseDataCount: 0,
            reachedStreamEnd: true
        )
    )
    #expect(
        !ShadowClientGameStreamHTTPTransport.shouldFailEndedHTTPResponseBeforeHeaders(
            responseDataCount: 1,
            reachedStreamEnd: true
        )
    )
    #expect(
        !ShadowClientGameStreamHTTPTransport.shouldFailEndedHTTPResponseBeforeHeaders(
            responseDataCount: 0,
            reachedStreamEnd: false
        )
    )
}

@Test("HTTP request write completion only finishes when the full request is sent")
func httpRequestWriteCompletionOnlyFinishesWhenTheFullRequestIsSent() {
    #expect(
        ShadowClientGameStreamHTTPTransport.isHTTPRequestWriteComplete(
            requestOffset: 128,
            requestDataCount: 128
        )
    )
    #expect(
        !ShadowClientGameStreamHTTPTransport.isHTTPRequestWriteComplete(
            requestOffset: 127,
            requestDataCount: 128
        )
    )
}

@Test("Launch parameter builder includes Lumen virtual display request when enabled")
func launchParameterBuilderIncludesLumenVirtualDisplayRequest() {
    let parameters = NativeGameStreamControlClient.makeLaunchParameters(
        appID: 881_448_767,
        settings: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false,
            preferVirtualDisplay: true
        ),
        remoteInputKey: Data([0x01, 0x02, 0x03, 0x04]),
        remoteInputKeyID: 7,
        surroundAudioInfo: 131_075,
        localAudioPlayMode: "0"
    )

    #expect(parameters["virtualDisplay"] == "1")
    #expect(parameters["corever"] == "1")
}

@Test("Launch parameter builder omits Lumen virtual display request by default")
func launchParameterBuilderOmitsLumenVirtualDisplayRequestByDefault() {
    let parameters = NativeGameStreamControlClient.makeLaunchParameters(
        appID: 1,
        settings: .init(
            width: 1280,
            height: 720,
            fps: 60,
            bitrateKbps: 10_000,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false
        ),
        remoteInputKey: Data([0xAA]),
        remoteInputKeyID: 9,
        surroundAudioInfo: 131_075,
        localAudioPlayMode: "1"
    )

    #expect(parameters["virtualDisplay"] == nil)
    #expect(parameters["corever"] == "1")
}

@Test("Launch parameter builder includes Lumen display scale contract when requested")
func launchParameterBuilderIncludesLumenDisplayScaleContract() {
    let parameters = NativeGameStreamControlClient.makeLaunchParameters(
        appID: 1,
        settings: .init(
            width: 1194,
            height: 790,
            fps: 60,
            bitrateKbps: 10_000,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false,
            resolutionScalePercent: 200,
            requestHiDPI: true
        ),
        remoteInputKey: Data([0xAA]),
        remoteInputKeyID: 9,
        surroundAudioInfo: 131_075,
        localAudioPlayMode: "1"
    )

    #expect(parameters["scaleFactor"] == "200")
    #expect(parameters["clientDisplayScalePercent"] == "200")
    #expect(parameters["clientDisplayHiDPI"] == "1")
    #expect(parameters["clientSinkScalePercent"] == "200")
    #expect(parameters["clientSinkHiDPI"] == "1")
    #expect(parameters["clientSinkModeIsLogical"] == "1")
    #expect(parameters["requestedDynamicRangeTransport"] == "sdr")
    #expect(parameters["clientSinkSupportsFrameGatedHDR"] == "0")
    #expect(parameters["clientSinkSupportsHDRTileOverlay"] == "0")
    #expect(parameters["clientSinkSupportsPerFrameHDRMetadata"] == "0")
    #expect(parameters["corever"] == "1")
}

@Test("Launch parameter builder includes Lumen client display profile when provided")
func launchParameterBuilderIncludesLumenClientDisplayProfile() {
    let parameters = NativeGameStreamControlClient.makeLaunchParameters(
        appID: 1,
        settings: .init(
            width: 1194,
            height: 790,
            fps: 60,
            bitrateKbps: 10_000,
            preferredCodec: .auto,
            enableHDR: true,
            enableSurroundAudio: false,
            lowLatencyMode: false,
            resolutionScalePercent: 200,
            requestHiDPI: true
        ),
        remoteInputKey: Data([0xAA]),
        remoteInputKeyID: 9,
        surroundAudioInfo: 131_075,
        localAudioPlayMode: "1",
        clientDisplayCharacteristics: .init(
            gamut: .displayP3,
            transfer: .pq,
            scalePercent: 200,
            hiDPIEnabled: true,
            supportsFrameGatedHDR: true,
            supportsPerFrameHDRMetadata: true,
            currentEDRHeadroom: 3.2,
            potentialEDRHeadroom: 8.0,
            currentPeakLuminanceNits: 320,
            potentialPeakLuminanceNits: 800
        )
    )

    #expect(parameters["clientDisplayGamut"] == "display-p3")
    #expect(parameters["clientDisplayTransfer"] == "pq")
    #expect(parameters["clientDisplayScalePercent"] == "200")
    #expect(parameters["clientDisplayHiDPI"] == "1")
    #expect(parameters["clientDisplayCurrentEDRHeadroom"] == "3.2")
    #expect(parameters["clientDisplayPotentialEDRHeadroom"] == "8.0")
    #expect(parameters["clientDisplayCurrentPeakLuminanceNits"] == "320")
    #expect(parameters["clientDisplayPotentialPeakLuminanceNits"] == "800")
    #expect(parameters["clientSinkGamut"] == "display-p3")
    #expect(parameters["clientSinkTransfer"] == "pq")
    #expect(parameters["clientSinkScalePercent"] == "200")
    #expect(parameters["clientSinkHiDPI"] == "1")
    #expect(parameters["clientSinkModeIsLogical"] == "1")
    #expect(parameters["clientSinkCurrentEDRHeadroom"] == "3.2")
    #expect(parameters["clientSinkPotentialEDRHeadroom"] == "8.0")
    #expect(parameters["clientSinkCurrentPeakLuminanceNits"] == "320")
    #expect(parameters["clientSinkPotentialPeakLuminanceNits"] == "800")
    #expect(parameters["requestedDynamicRangeTransport"] == "frame-gated-hdr")
    #expect(parameters["clientSinkSupportsFrameGatedHDR"] == "1")
    #expect(parameters["clientSinkSupportsHDRTileOverlay"] == "0")
    #expect(parameters["clientSinkSupportsPerFrameHDRMetadata"] == "1")
    #expect(parameters["corever"] == "1")
}
