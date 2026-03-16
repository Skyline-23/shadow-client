import Foundation
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

@Test("Pairchallenge certificate-required transport failure is treated as non-fatal")
func pairchallengeCertificateRequiredFailureIsNonFatal() {
    let error = ShadowClientGameStreamError.requestFailed(
        "Pairing pairchallenge failed: TLSV1_ALERT_CERTIFICATE_REQUIRED: certificate required"
    )

    #expect(NativeGameStreamControlClient.isNonFatalPairChallengeTransportFailure(error))
}

@Test("Pairchallenge transport only ignores certificate-required failures")
func pairchallengeOnlyIgnoresCertificateRequiredFailure() {
    let timeoutError = ShadowClientGameStreamError.requestFailed(
        "Pairing pairchallenge failed: The operation timed out."
    )
    let rejectedError = ShadowClientGameStreamError.responseRejected(
        code: 401,
        message: "Pairing pairchallenge rejected by host."
    )

    #expect(!NativeGameStreamControlClient.isNonFatalPairChallengeTransportFailure(timeoutError))
    #expect(!NativeGameStreamControlClient.isNonFatalPairChallengeTransportFailure(rejectedError))
}

@Test("Pairchallenge does not pin the server certificate during pairing")
func pairchallengeDoesNotPinServerCertificateDuringPairing() {
    let serverCertificateDER = Data([0x01, 0x02, 0x03, 0x04])

    #expect(
        NativeGameStreamControlClient.pairChallengePinnedServerCertificateDER(
            serverCertificateDER: serverCertificateDER
        ) == nil
    )
}

@Test("HTTP request builder includes method headers and body length")
func httpRequestBuilderIncludesMethodHeadersAndBodyLength() {
    let url = URL(string: "https://desktop-lan.local:47984/actions/clipboard?type=text")!
    let requestData = ShadowClientGameStreamHTTPTransport.makeHTTPRequestData(
        url: url,
        host: "desktop-lan.local",
        method: "POST",
        headers: [
            "Content-Type": "text/plain; charset=utf-8",
        ],
        body: Data("hello".utf8)
    )

    let requestText = String(decoding: requestData, as: UTF8.self)
    #expect(requestText.contains("POST /actions/clipboard?type=text HTTP/1.1"))
    #expect(requestText.contains("Host: desktop-lan.local:47984"))
    #expect(requestText.contains("Content-Type: text/plain; charset=utf-8"))
    #expect(requestText.contains("Content-Length: 5"))
    #expect(requestText.hasSuffix("\r\n\r\nhello"))
}

@Test("HTTP transport keeps dual-stack targets while skipping loopback and scoped link-local fallbacks")
func httpTransportConnectionTargetsPreferUsableRemoteAddresses() {
    let targets = ShadowClientGameStreamHTTPTransport.connectionTargetCandidates(
        for: "desktop.local",
        resolvedHosts: [
            "fe80::1%bridge100",
            "::1",
            "2001:db8::20",
            "10.0.0.20",
            "10.0.0.20",
        ]
    )

    #expect(targets == ["2001:db8::20", "10.0.0.20"])
}

@Test("HTTP transport preserves loopback targets for localhost requests")
func httpTransportConnectionTargetsKeepLoopbackForLocalhost() {
    let targets = ShadowClientGameStreamHTTPTransport.connectionTargetCandidates(
        for: "localhost",
        resolvedHosts: [
            "::1",
            "127.0.0.1",
        ]
    )

    #expect(targets == ["::1", "127.0.0.1"])
}

@Test("HTTP transport rewrites HTTPS URLs for numeric IPv6 targets")
func httpTransportRewritesURLForNumericIPv6Targets() throws {
    let rewrittenURL = try ShadowClientGameStreamHTTPTransport.urlForConnectionTarget(
        URL(string: "https://desktop.local:47984/serverinfo")!,
        host: "2001:db8::20"
    )

    #expect(rewrittenURL.absoluteString == "https://[2001:db8::20]:47984/serverinfo")
}

@Test("Launch parameter builder includes Apollo virtual display request when enabled")
func launchParameterBuilderIncludesApolloVirtualDisplayRequest() {
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
}

@Test("Launch parameter builder omits Apollo virtual display request by default")
func launchParameterBuilderOmitsApolloVirtualDisplayRequestByDefault() {
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
}

@Test("Launch parameter builder includes Apollo scale factor when requested")
func launchParameterBuilderIncludesApolloScaleFactor() {
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
            resolutionScalePercent: 200
        ),
        remoteInputKey: Data([0xAA]),
        remoteInputKeyID: 9,
        surroundAudioInfo: 131_075,
        localAudioPlayMode: "1"
    )

    #expect(parameters["scaleFactor"] == "200")
}
