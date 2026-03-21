import Darwin
import Network
import Testing
@testable import ShadowClientFeatureHome

@Test("Streaming traffic policy maps prioritized media and control classes")
func streamingTrafficPolicyMapsPrioritizedClasses() {
    #expect(ShadowClientStreamingTrafficPolicy.rtsp(prioritized: true).nwServiceClass == .interactiveVideo)
    #expect(ShadowClientStreamingTrafficPolicy.video(prioritized: true).socketServiceType == NET_SERVICE_TYPE_VI)
    #expect(ShadowClientStreamingTrafficPolicy.audio(prioritized: true).socketServiceType == NET_SERVICE_TYPE_VO)
    #expect(ShadowClientStreamingTrafficPolicy.control(prioritized: true).nwServiceClass == .signaling)
}

@Test("Streaming traffic policy falls back to best effort when disabled")
func streamingTrafficPolicyFallsBackToBestEffort() {
    #expect(ShadowClientStreamingTrafficPolicy.rtsp(prioritized: false).nwServiceClass == .bestEffort)
    #expect(ShadowClientStreamingTrafficPolicy.video(prioritized: false).socketServiceType == NET_SERVICE_TYPE_BE)
    #expect(ShadowClientStreamingTrafficPolicy.audio(prioritized: false).socketServiceType == NET_SERVICE_TYPE_BE)
    #expect(ShadowClientStreamingTrafficPolicy.control(prioritized: false).nwServiceClass == .bestEffort)
}
