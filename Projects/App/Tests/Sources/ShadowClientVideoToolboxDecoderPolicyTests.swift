@testable import ShadowClientFeatureHome
import Testing

@Test("VideoToolbox decoder in-flight policy respects configured bounds")
func videoToolboxDecoderInFlightPolicyRespectsConfiguredBounds() {
    let minimum = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 1,
        activeProcessorCount: 1
    )
    let maximum = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 240,
        activeProcessorCount: 32
    )

    #expect(minimum >= ShadowClientVideoDecoderDefaults.minimumInFlightDecodeRequests)
    #expect(maximum <= ShadowClientVideoDecoderDefaults.maximumInFlightDecodeRequests)
}

@Test("VideoToolbox decoder in-flight policy increases with fps and available cores")
func videoToolboxDecoderInFlightPolicyIncreasesWithFpsAndCores() {
    let baseline = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 60,
        activeProcessorCount: 4
    )
    let higherFPS = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 120,
        activeProcessorCount: 4
    )
    let higherCoreCount = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 60,
        activeProcessorCount: 12
    )

    #expect(higherFPS >= baseline)
    #expect(higherCoreCount >= baseline)
}
