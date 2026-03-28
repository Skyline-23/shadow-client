import Testing
@testable import ShadowClientFeatureHome

@Test("HDR compositor disables EDR when partial overlay metadata contains no regions")
func hdrCompositorDisablesEDRForEmptyPartialOverlayState() {
    let allowsExtendedDynamicRange =
        ShadowClientRealtimeSessionHDRCompositor.allowsExtendedDynamicRange(
            dynamicRangeMode: .hdr,
            hdrFrameState: .init(
                content: .partialHDROverlay,
                effectiveFromFrameNumber: 0,
                staticMetadata: nil,
                overlayRegions: []
            )
        )

    #expect(!allowsExtendedDynamicRange)
}

@Test("HDR compositor keeps EDR enabled for partial overlay regions on HDR sessions")
func hdrCompositorKeepsEDREnabledForPartialOverlayRegions() {
    let allowsExtendedDynamicRange =
        ShadowClientRealtimeSessionHDRCompositor.allowsExtendedDynamicRange(
            dynamicRangeMode: .hdr,
            hdrFrameState: .init(
                content: .partialHDROverlay,
                effectiveFromFrameNumber: 0,
                staticMetadata: nil,
                overlayRegions: [
                    .init(x: 10, y: 20, width: 30, height: 40, metadata: nil)
                ]
            )
        )

    #expect(allowsExtendedDynamicRange)
}

@Test("HDR compositor sink capability requires EDR headroom and Metal")
func hdrCompositorSinkCapabilityRequiresEDRAndMetal() {
    let missingMetal = ShadowClientRealtimeSessionHDRCompositor.sinkCapabilities(
        potentialEDRHeadroom: 2.0,
        hasMetalRenderer: false
    )
    let missingEDR = ShadowClientRealtimeSessionHDRCompositor.sinkCapabilities(
        potentialEDRHeadroom: 1.0,
        hasMetalRenderer: true
    )
    let available = ShadowClientRealtimeSessionHDRCompositor.sinkCapabilities(
        potentialEDRHeadroom: 2.0,
        hasMetalRenderer: true
    )

    #expect(!missingMetal.supportsFrameGatedHDR)
    #expect(!missingMetal.supportsHDRTileOverlay)
    #expect(!missingMetal.supportsPerFrameHDRMetadata)
    #expect(!missingEDR.supportsFrameGatedHDR)
    #expect(!missingEDR.supportsHDRTileOverlay)
    #expect(!missingEDR.supportsPerFrameHDRMetadata)
    #expect(available.supportsFrameGatedHDR)
    #expect(available.supportsHDRTileOverlay)
    #expect(available.supportsPerFrameHDRMetadata)
}
