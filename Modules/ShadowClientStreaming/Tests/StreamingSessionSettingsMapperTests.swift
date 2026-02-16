import Testing
@testable import ShadowClientStreaming

@Test("Settings mapper enables HDR10 and 5.1 audio when preference, capabilities, and signal health all pass")
func settingsMapperEnablesHDRAndSurroundWhenEligible() {
    let mapper = StreamingSessionSettingsMapper()
    let preferences = StreamingUserPreferences(
        preferHDR: true,
        preferSurroundAudio: true,
        lowLatencyMode: false
    )
    let capabilities = HostStreamingCapabilities(
        supportsHDR10: true,
        supportsSurround51: true
    )
    let signal = StreamingNetworkSignal(jitterMs: 8.0, packetLossPercent: 0.4)

    let configuration = mapper.map(
        preferences: preferences,
        capabilities: capabilities,
        signal: signal
    )

    #expect(configuration.hdrVideoMode == .hdr10)
    #expect(configuration.audioMode == .surround51)
}

@Test("Settings mapper forces stereo in low-latency mode while preserving HDR eligibility")
func settingsMapperForcesStereoInLowLatencyMode() {
    let mapper = StreamingSessionSettingsMapper()
    let preferences = StreamingUserPreferences(
        preferHDR: true,
        preferSurroundAudio: true,
        lowLatencyMode: true
    )
    let capabilities = HostStreamingCapabilities(
        supportsHDR10: true,
        supportsSurround51: true
    )
    let signal = StreamingNetworkSignal(jitterMs: 9.0, packetLossPercent: 0.5)

    let configuration = mapper.map(
        preferences: preferences,
        capabilities: capabilities,
        signal: signal
    )

    #expect(configuration.hdrVideoMode == .hdr10)
    #expect(configuration.audioMode == .stereo)
}

@Test("Settings mapper disables HDR and surround when network quality exceeds thresholds")
func settingsMapperDisablesHDRAndSurroundOnNetworkDegradation() {
    let mapper = StreamingSessionSettingsMapper()
    let preferences = StreamingUserPreferences(
        preferHDR: true,
        preferSurroundAudio: true,
        lowLatencyMode: false
    )
    let capabilities = HostStreamingCapabilities(
        supportsHDR10: true,
        supportsSurround51: true
    )
    let signal = StreamingNetworkSignal(jitterMs: 42.0, packetLossPercent: 4.2)

    let configuration = mapper.map(
        preferences: preferences,
        capabilities: capabilities,
        signal: signal
    )

    #expect(configuration.hdrVideoMode == .off)
    #expect(configuration.audioMode == .stereo)
}

@Test("Settings mapper honors host capability limits even when preference and signal allow high quality")
func settingsMapperHonorsHostCapabilityLimits() {
    let mapper = StreamingSessionSettingsMapper()
    let preferences = StreamingUserPreferences(
        preferHDR: true,
        preferSurroundAudio: true,
        lowLatencyMode: false
    )
    let capabilities = HostStreamingCapabilities(
        supportsHDR10: false,
        supportsSurround51: false
    )
    let signal = StreamingNetworkSignal(jitterMs: 4.0, packetLossPercent: 0.1)

    let configuration = mapper.map(
        preferences: preferences,
        capabilities: capabilities,
        signal: signal
    )

    #expect(configuration.hdrVideoMode == .off)
    #expect(configuration.audioMode == .stereo)
}
