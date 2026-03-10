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
