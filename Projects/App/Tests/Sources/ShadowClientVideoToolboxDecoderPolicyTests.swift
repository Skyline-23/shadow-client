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

@Test("VideoToolbox decoder in-flight policy scales up under heavier frame workloads")
func videoToolboxDecoderInFlightPolicyScalesUpForHeavierWorkload() {
    let baseline = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 60,
        frameWidth: 1_920,
        frameHeight: 1_080,
        activeProcessorCount: 8
    )
    let higherFPSAtSameResolution = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 120,
        frameWidth: 1_920,
        frameHeight: 1_080,
        activeProcessorCount: 8
    )
    let ultraHD = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 60,
        frameWidth: 3_840,
        frameHeight: 2_160,
        activeProcessorCount: 8
    )
    let higherCoreCount = ShadowClientVideoToolboxDecoder.recommendedMaximumInFlightDecodeRequests(
        for: 60,
        frameWidth: 1_920,
        frameHeight: 1_080,
        activeProcessorCount: 12
    )

    #expect(higherFPSAtSameResolution >= baseline)
    #expect(ultraHD >= baseline)
    #expect(higherCoreCount >= baseline)
}
