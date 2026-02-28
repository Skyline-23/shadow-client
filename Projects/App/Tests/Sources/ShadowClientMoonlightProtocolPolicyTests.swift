import Testing
@testable import ShadowClientFeatureHome

@Test("Moonlight audio payload defaults remain protocol aligned")
func moonlightAudioPayloadDefaultsRemainProtocolAligned() {
    #expect(ShadowClientMoonlightProtocolPolicy.Audio.primaryPayloadType == 97)
    #expect(ShadowClientMoonlightProtocolPolicy.Audio.fecWrapperPayloadType == 127)
    #expect(ShadowClientMoonlightProtocolPolicy.Audio.fecDataShardsPerBlock == 4)
    #expect(ShadowClientMoonlightProtocolPolicy.Audio.fecParityShardsPerBlock == 2)
    #expect(ShadowClientMoonlightProtocolPolicy.Audio.fecHeaderLength == 12)
}

@Test("Moonlight PLC sample sizing follows packet duration")
func moonlightPLCSampleSizingFollowsPacketDuration() {
    let minSamples = 240
    let maxSamples = 2_880

    let fiveMs = ShadowClientMoonlightProtocolPolicy.Audio.plcSamplesPerChannel(
        sampleRate: 48_000,
        packetDurationMs: 5,
        minimumPacketSamples: minSamples,
        maximumPacketSamples: maxSamples
    )
    let tenMs = ShadowClientMoonlightProtocolPolicy.Audio.plcSamplesPerChannel(
        sampleRate: 48_000,
        packetDurationMs: 10,
        minimumPacketSamples: minSamples,
        maximumPacketSamples: maxSamples
    )

    #expect(fiveMs == 240)
    #expect(tenMs == 480)
}

@Test("Moonlight audio burst caps map to FEC geometry")
func moonlightAudioBurstCapsMapToFECGeometry() {
    #expect(
        ShadowClientMoonlightProtocolPolicy.Audio.recoveredPacketsPerBurstCap(
            availableOutputSlots: 10
        ) == 2
    )
    #expect(
        ShadowClientMoonlightProtocolPolicy.Audio.concealmentPacketsPerBurstCap(
            availableOutputSlots: 10
        ) == 4
    )
}

@Test("Moonlight AV1 sync frame gating follows IDR and RFI rules")
func moonlightAV1SyncFrameGatingFollowsIDRAndRFIRules() {
    #expect(
        ShadowClientMoonlightProtocolPolicy.AV1.isSyncFrameType(
            2,
            allowsReferenceInvalidatedFrame: false
        )
    )
    #expect(
        !ShadowClientMoonlightProtocolPolicy.AV1.isSyncFrameType(
            5,
            allowsReferenceInvalidatedFrame: false
        )
    )
    #expect(
        ShadowClientMoonlightProtocolPolicy.AV1.isSyncFrameType(
            5,
            allowsReferenceInvalidatedFrame: true
        )
    )
    #expect(
        !ShadowClientMoonlightProtocolPolicy.AV1.isSyncFrameType(
            nil,
            allowsReferenceInvalidatedFrame: true
        )
    )
}
