import Darwin
import Testing
@testable import ShadowClientFeatureHome

@Test("UDP datagram socket ignores transient connected receive failures")
func udpDatagramSocketIgnoresTransientConnectedReceiveFailures() {
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ECONNREFUSED
        )
    )
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ECONNRESET
        )
    )
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ENETUNREACH
        )
    )
    #expect(
        !ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            EINVAL
        )
    )
}

@Test("UDP datagram socket ignores transient connected send failures")
func udpDatagramSocketIgnoresTransientConnectedSendFailures() {
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatSendFailureAsTransient(
            ECONNREFUSED
        )
    )
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatSendFailureAsTransient(
            ENOTCONN
        )
    )
    #expect(
        !ShadowClientUDPDatagramSocket.shouldTreatSendFailureAsTransient(
            EINVAL
        )
    )
}

@Test("UDP datagram socket error reports operation and transient state")
func udpDatagramSocketErrorReportsOperationAndTransientState() {
    let error = ShadowClientUDPDatagramSocketError.systemCallFailed(
        operation: .receive,
        code: ECONNRESET,
        message: "Connection reset by peer",
        transient: true
    )

    #expect(error.isTransient)
    #expect(error.operation == .receive)
    #expect(error.localizedDescription == "receive failed (\(ECONNRESET), transient=true): Connection reset by peer")
}
