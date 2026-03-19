import Darwin
import Testing
@testable import ShadowClientFeatureHome

@Test("UDP datagram socket ignores transient connected receive failures")
func udpDatagramSocketIgnoresTransientConnectedReceiveFailures() {
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ECONNREFUSED,
            useConnectedSocket: true
        )
    )
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ECONNRESET,
            useConnectedSocket: true
        )
    )
    #expect(
        ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ENETUNREACH,
            useConnectedSocket: true
        )
    )
    #expect(
        !ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            EINVAL,
            useConnectedSocket: true
        )
    )
    #expect(
        !ShadowClientUDPDatagramSocket.shouldTreatReceiveFailureAsTransient(
            ECONNREFUSED,
            useConnectedSocket: false
        )
    )
}
