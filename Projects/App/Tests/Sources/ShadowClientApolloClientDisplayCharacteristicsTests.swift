import CoreGraphics
import Testing
@testable import ShadowClientFeatureHome

@Test("Mac transfer contract keeps Display P3 HDR desktops on SDR transfer")
func macTransferContractKeepsDisplayP3HDRDesktopsOnSDRTransfer() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: true,
        environment: .colorManagedDesktop(
            CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        )
    )

    #expect(transfer == .sdr)
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

@Test("UIKit transfer contract keeps HDR-capable clients on SDR desktop transfer")
func uikitTransferContractKeepsHDRCapableClientsOnSDRTransfer() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: true,
        environment: .compositedUIKit
    )

    #expect(transfer == .sdr)
}

@Test("UIKit transfer contract stays SDR when HDR is disabled")
func uikitTransferContractFallsBackToSDRWhenHDRIsDisabled() {
    let transfer = ShadowClientApolloClientDisplayTransferContract.resolve(
        hdrEnabled: false,
        environment: .compositedUIKit
    )

    #expect(transfer == .sdr)
}
