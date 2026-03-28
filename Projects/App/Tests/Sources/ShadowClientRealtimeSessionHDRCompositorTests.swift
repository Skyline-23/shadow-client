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

@Test("HDR compositor sink capability advertises overlay metadata support when Metal HDR composition is available")
func hdrCompositorSinkCapabilityAdvertisesOverlayMetadataSupport() {
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

@Test("HDR compositor prefers overlay region metadata over frame and negotiated metadata")
func hdrCompositorPrefersOverlayRegionMetadata() {
    let negotiatedMetadata = makeCompositorTestHDRMetadata(maxDisplayLuminance: 1_000)
    let frameMetadata = makeCompositorTestHDRMetadata(maxDisplayLuminance: 1_200)
    let regionMetadata = makeCompositorTestHDRMetadata(maxDisplayLuminance: 1_600)
    let resolved = ShadowClientRealtimeSessionHDRCompositor.resolvedOverlayHDRMetadata(
        overlayRegion: .init(
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            metadata: regionMetadata
        ),
        hdrFrameState: .init(
            content: .partialHDROverlay,
            effectiveFromFrameNumber: 0,
            staticMetadata: frameMetadata,
            overlayRegions: []
        ),
        defaultHDRMetadata: negotiatedMetadata
    )

    #expect(resolved == regionMetadata)
}

@Test("HDR compositor falls back from frame metadata to negotiated metadata for overlay regions")
func hdrCompositorFallsBackFromFrameMetadataToNegotiatedMetadata() {
    let negotiatedMetadata = makeCompositorTestHDRMetadata(maxDisplayLuminance: 1_000)
    let frameMetadata = makeCompositorTestHDRMetadata(maxDisplayLuminance: 1_200)
    let fallbackToFrame = ShadowClientRealtimeSessionHDRCompositor.resolvedOverlayHDRMetadata(
        overlayRegion: .init(
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            metadata: nil
        ),
        hdrFrameState: .init(
            content: .partialHDROverlay,
            effectiveFromFrameNumber: 0,
            staticMetadata: frameMetadata,
            overlayRegions: []
        ),
        defaultHDRMetadata: negotiatedMetadata
    )
    let fallbackToNegotiated = ShadowClientRealtimeSessionHDRCompositor.resolvedOverlayHDRMetadata(
        overlayRegion: .init(
            x: 0,
            y: 0,
            width: 10,
            height: 10,
            metadata: nil
        ),
        hdrFrameState: .init(
            content: .partialHDROverlay,
            effectiveFromFrameNumber: 0,
            staticMetadata: nil,
            overlayRegions: []
        ),
        defaultHDRMetadata: negotiatedMetadata
    )

    #expect(fallbackToFrame == frameMetadata)
    #expect(fallbackToNegotiated == negotiatedMetadata)
}

private func makeCompositorTestHDRMetadata(
    maxDisplayLuminance: UInt16
) -> ShadowClientHDRMetadata {
    ShadowClientHDRMetadata(
        displayPrimaries: [
            .init(x: 100, y: 200),
            .init(x: 300, y: 400),
            .init(x: 500, y: 600),
        ],
        whitePoint: .init(x: 700, y: 800),
        maxDisplayLuminance: maxDisplayLuminance,
        minDisplayLuminance: 1,
        maxContentLightLevel: maxDisplayLuminance,
        maxFrameAverageLightLevel: maxDisplayLuminance / 2,
        maxFullFrameLuminance: 0
    )
}
