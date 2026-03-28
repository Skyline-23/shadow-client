import CoreGraphics
import Testing
@testable import ShadowClientFeatureHome

@Test("Mac transfer contract defaults HDR desktops to PQ transfer")
func macTransferContractDefaultsHDRDesktopsToPQTransfer() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: true,
        environment: .colorManagedDesktop(
            CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        )
    )

    #expect(transfer == .pq)
}

@Test("Mac transfer contract preserves explicit PQ displays")
func macTransferContractPreservesExplicitPQDisplays() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: true,
        environment: .colorManagedDesktop(
            CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
        )
    )

    #expect(transfer == .pq)
}

@Test("Mac transfer contract preserves explicit HLG displays")
func macTransferContractPreservesExplicitHLGDisplays() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: true,
        environment: .colorManagedDesktop(
            CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? CGColorSpaceCreateDeviceRGB()
        )
    )

    #expect(transfer == .hlg)
}

@Test("Mac transfer contract falls back to SDR when HDR is disabled")
func macTransferContractFallsBackToSDRWhenHDRIsDisabled() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: false,
        environment: .colorManagedDesktop(
            CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
        )
    )

    #expect(transfer == .sdr)
}

@Test("UIKit transfer contract defaults HDR-capable clients to PQ transfer")
func uikitTransferContractDefaultsHDRCapableClientsToPQTransfer() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: true,
        environment: .compositedUIKit
    )

    #expect(transfer == .pq)
}

@Test("UIKit transfer contract stays SDR when HDR is disabled")
func uikitTransferContractFallsBackToSDRWhenHDRIsDisabled() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: false,
        environment: .compositedUIKit
    )

    #expect(transfer == .sdr)
}

@Test("Apollo sink capability remains frame-gated capable on SDR transfers")
func apolloSinkCapabilityRemainsFrameGatedCapableOnSDRTransfers() {
    let characteristics = ShadowClientApolloClientDisplayCharacteristics(
        gamut: .displayP3,
        transfer: .sdr,
        scalePercent: 100,
        hiDPIEnabled: false,
        supportsFrameGatedHDR: true,
        supportsPerFrameHDRMetadata: true
    )

    #expect(characteristics.supportsFrameGatedHDR)
    #expect(!characteristics.supportsHDRTileOverlay)
    #expect(characteristics.supportsPerFrameHDRMetadata)
    #expect(characteristics.requestedDynamicRangeTransport(hdrRequested: true) == .sdr)
}

@Test("Apollo sink request promotes HDR sink transfers to frame-gated transport")
func apolloSinkRequestPromotesHDRSinkTransfersToFrameGatedTransport() {
    let characteristics = ShadowClientApolloClientDisplayCharacteristics(
        gamut: .displayP3,
        transfer: .pq,
        scalePercent: 100,
        hiDPIEnabled: false,
        supportsFrameGatedHDR: true,
        supportsPerFrameHDRMetadata: true
    )

    #expect(characteristics.requestedDynamicRangeTransport(hdrRequested: true) == .frameGatedHDR)
}

@Test("Apollo sink request falls back to SDR when HDR compositor support is unavailable")
func apolloSinkRequestFallsBackToSDRWithoutHDRSinkCapability() {
    let characteristics = ShadowClientApolloClientDisplayCharacteristics(
        gamut: .displayP3,
        transfer: .pq,
        scalePercent: 100,
        hiDPIEnabled: false
    )

    #expect(!characteristics.supportsFrameGatedHDR)
    #expect(!characteristics.supportsPerFrameHDRMetadata)
    #expect(characteristics.requestedDynamicRangeTransport(hdrRequested: true) == .sdr)
}
