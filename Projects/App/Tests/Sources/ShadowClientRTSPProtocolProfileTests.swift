import Network
import Testing
@testable import ShadowClientFeatureHome

@Test("RTSP profile uses wildcard bind host when local host is unresolved")
func rtspProfileUsesWildcardBindHostWhenLocalHostIsNil() {
    let host = ShadowClientRTSPProtocolProfile.localBindHost(from: nil)

    #expect(String(describing: host) == ShadowClientRTSPProtocolProfile.wildcardIPv4HostAddress)
}

@Test("RTSP profile preserves resolved local bind host")
func rtspProfilePreservesResolvedBindHost() {
    let resolvedHost = NWEndpoint.Host("192.168.10.50")
    let host = ShadowClientRTSPProtocolProfile.localBindHost(from: resolvedHost)

    #expect(String(describing: host) == "192.168.10.50")
}
