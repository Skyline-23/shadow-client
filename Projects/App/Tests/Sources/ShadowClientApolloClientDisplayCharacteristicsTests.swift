import CoreGraphics
import Testing
@testable import ShadowClientFeatureHome

@Test("Mac transfer contract keeps Display P3 HDR desktops on SDR transfer")
func macTransferContractKeepsDisplayP3HDRDesktopsOnSDRTransfer() {
    let transfer = ShadowClientApolloClientDisplayCharacteristicsResolver.macTransferContract(
        for: CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB(),
        hdrEnabled: true
    )

    #expect(transfer == .sdr)
}

@Test("Mac transfer contract preserves explicit PQ displays")
func macTransferContractPreservesExplicitPQDisplays() {
    let transfer = ShadowClientApolloClientDisplayCharacteristicsResolver.macTransferContract(
        for: CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        hdrEnabled: true
    )

    #expect(transfer == .pq)
}

@Test("Mac transfer contract preserves explicit HLG displays")
func macTransferContractPreservesExplicitHLGDisplays() {
    let transfer = ShadowClientApolloClientDisplayCharacteristicsResolver.macTransferContract(
        for: CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? CGColorSpaceCreateDeviceRGB(),
        hdrEnabled: true
    )

    #expect(transfer == .hlg)
}

@Test("Mac transfer contract falls back to SDR when HDR is disabled")
func macTransferContractFallsBackToSDRWhenHDRIsDisabled() {
    let transfer = ShadowClientApolloClientDisplayCharacteristicsResolver.macTransferContract(
        for: CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        hdrEnabled: false
    )

    #expect(transfer == .sdr)
}

@Test("UIKit transfer contract keeps HDR-capable clients on SDR desktop transfer")
func uikitTransferContractKeepsHDRCapableClientsOnSDRTransfer() {
    let transfer = ShadowClientApolloClientDisplayCharacteristicsResolver.uikitTransferContract(
        hdrEnabled: true
    )

    #expect(transfer == .sdr)
}

@Test("UIKit transfer contract stays SDR when HDR is disabled")
func uikitTransferContractFallsBackToSDRWhenHDRIsDisabled() {
    let transfer = ShadowClientApolloClientDisplayCharacteristicsResolver.uikitTransferContract(
        hdrEnabled: false
    )

    #expect(transfer == .sdr)
}
