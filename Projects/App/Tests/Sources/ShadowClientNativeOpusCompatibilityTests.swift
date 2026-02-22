import Testing
@testable import ShadowClientNativeAudioDecoding

@Test("Opus semantic version parser handles plain semver")
func opusSemanticVersionParserHandlesPlainSemver() {
    let version = ShadowClientNativeOpusSemanticVersion(parsing: "0.1.0")

    #expect(version != nil)
    #expect(version?.major == 0)
    #expect(version?.minor == 1)
    #expect(version?.patch == 0)
}

@Test("Opus semantic version parser extracts version from prefixed runtime string")
func opusSemanticVersionParserExtractsVersionFromRuntimeString() {
    let version = ShadowClientNativeOpusSemanticVersion(parsing: "libopus 1.5.2-rc1")

    #expect(version != nil)
    #expect(version?.major == 1)
    #expect(version?.minor == 5)
    #expect(version?.patch == 2)
}

@Test("Opus compatibility profile stays conservative when no tag can be resolved")
func opusCompatibilityProfileStaysConservativeWhenNoTagCanBeResolved() {
    let profile = ShadowClientNativeOpusCompatibilityProfile.detect(
        runtimeLibopusVersionString: "unknown"
    )

    #expect(profile.resolvedRuntimeLibopusTag == nil)
    #expect(!profile.supportsMultistreamLayout)
    #expect(!profile.supportsInBandFEC)
    #expect(profile.maximumSupportedPayloadBytes == 1_500)
}

@Test("Opus compatibility profile resolves stable tags and enables full path")
func opusCompatibilityProfileResolvesStableTagsAndEnablesFullPath() {
    let profile = ShadowClientNativeOpusCompatibilityProfile.detect(
        runtimeLibopusVersionString: "libopus 1.5.2"
    )

    #expect(profile.resolvedRuntimeLibopusTag == .v1_5_2)
    #expect(profile.supportsMultistreamLayout)
    #expect(profile.supportsInBandFEC)
    #expect(profile.maximumSupportedPayloadBytes == 8_192)
    #expect(profile.supportsSurroundDecoding(channelCount: 6))
}

@Test("Opus compatibility profile disables FEC for older runtime tags")
func opusCompatibilityProfileDisablesFECForOlderRuntimeTags() {
    let profile = ShadowClientNativeOpusCompatibilityProfile.detect(
        runtimeLibopusVersionString: "libopus 1.0.3"
    )

    #expect(profile.resolvedRuntimeLibopusTag == .v1_0_3)
    #expect(!profile.supportsInBandFEC)
    #expect(profile.supportsMultistreamLayout)
    #expect(profile.maximumSupportedPayloadBytes == 1_500)
}
