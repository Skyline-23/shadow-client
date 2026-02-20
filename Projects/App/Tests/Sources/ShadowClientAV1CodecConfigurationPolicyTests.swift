import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("AV1 policy prefers explicit codec configuration when available")
func av1PolicyPrefersExplicitConfiguration() {
    let current = [Data([0x81, 0x00, 0x0C, 0x00])]
    let explicit = [Data([0x81, 0x20, 0x40, 0x00])]

    let resolved = ShadowClientAV1CodecConfigurationPolicy.resolve(
        currentParameterSets: current,
        currentOrigin: .stream,
        explicitParameterSets: explicit,
        discoveredConfiguration: Data([0x81, 0x00, 0x4C, 0x00]),
        fallbackConfiguration: Data([0x81, 0x00, 0x0C, 0x00])
    )

    #expect(resolved.parameterSets == explicit)
    #expect(resolved.origin == .explicit)
}

@Test("AV1 policy seeds from discovered stream configuration when no current state exists")
func av1PolicyUsesDiscoveredConfigurationOnEmptyState() {
    let discovered = Data([0x81, 0x00, 0x4C, 0x00])

    let resolved = ShadowClientAV1CodecConfigurationPolicy.resolve(
        currentParameterSets: [],
        currentOrigin: nil,
        explicitParameterSets: [],
        discoveredConfiguration: discovered,
        fallbackConfiguration: Data([0x81, 0x00, 0x0C, 0x00])
    )

    #expect(resolved.parameterSets == [discovered])
    #expect(resolved.origin == .stream)
}

@Test("AV1 policy falls back when no stream or explicit configuration exists")
func av1PolicyUsesFallbackWhenNoConfigurationExists() {
    let fallback = Data([0x81, 0x00, 0x0C, 0x00])

    let resolved = ShadowClientAV1CodecConfigurationPolicy.resolve(
        currentParameterSets: [],
        currentOrigin: nil,
        explicitParameterSets: [],
        discoveredConfiguration: nil,
        fallbackConfiguration: fallback
    )

    #expect(resolved.parameterSets == [fallback])
    #expect(resolved.origin == .fallback)
}

@Test("AV1 policy upgrades fallback configuration once stream config is discovered")
func av1PolicyUpgradesFromFallbackToStream() {
    let fallback = Data([0x81, 0x00, 0x0C, 0x00])
    let discovered = Data([0x81, 0x00, 0x4C, 0x00])

    let resolved = ShadowClientAV1CodecConfigurationPolicy.resolve(
        currentParameterSets: [fallback],
        currentOrigin: .fallback,
        explicitParameterSets: [],
        discoveredConfiguration: discovered,
        fallbackConfiguration: fallback
    )

    #expect(resolved.parameterSets == [discovered])
    #expect(resolved.origin == .stream)
}

@Test("AV1 policy keeps stable stream configuration and avoids churn")
func av1PolicyKeepsStableStreamConfiguration() {
    let currentStreamConfiguration = Data([0x81, 0x00, 0x4C, 0x00])
    let laterDiscoveredConfiguration = Data([0x81, 0x20, 0x40, 0x00])

    let resolved = ShadowClientAV1CodecConfigurationPolicy.resolve(
        currentParameterSets: [currentStreamConfiguration],
        currentOrigin: .stream,
        explicitParameterSets: [],
        discoveredConfiguration: laterDiscoveredConfiguration,
        fallbackConfiguration: Data([0x81, 0x00, 0x0C, 0x00])
    )

    #expect(resolved.parameterSets == [currentStreamConfiguration])
    #expect(resolved.origin == .stream)
}
