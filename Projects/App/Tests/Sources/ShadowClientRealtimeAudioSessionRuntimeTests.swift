import Testing
@testable import ShadowClientFeatureHome

@Test("Payload type adaptation accepts dynamic payload type changes")
func payloadTypeAdaptationAcceptsDynamicChanges() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 98,
        current: 97
    )

    #expect(adapted == 98)
}

@Test("Payload type adaptation ignores matching payload types")
func payloadTypeAdaptationIgnoresMatching() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 97,
        current: 97
    )

    #expect(adapted == nil)
}

@Test("Payload type adaptation rejects RTCP/control-like payload types")
func payloadTypeAdaptationRejectsControlValues() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 72,
        current: 97
    )

    #expect(adapted == nil)
}
