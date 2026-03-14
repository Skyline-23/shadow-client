import CoreGraphics
import SwiftUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Auto resolution uses display-sized metrics instead of a smaller viewport")
func autoResolutionPrefersDisplayMetrics() {
    let resolved = ShadowClientAutoResolutionPolicy.resolvePixelSize(
        displayLogicalSize: CGSize(width: 1728, height: 1117),
        safeAreaInsets: .init(),
        scale: 2.0
    )

    #expect(resolved == CGSize(width: 3456, height: 2234))
}

@Test("Auto resolution subtracts safe area before scaling")
func autoResolutionSubtractsSafeAreaBeforeScaling() {
    let resolved = ShadowClientAutoResolutionPolicy.resolvePixelSize(
        displayLogicalSize: CGSize(width: 1194, height: 834),
        safeAreaInsets: .init(top: 24, leading: 0, bottom: 20, trailing: 0),
        scale: 2.0
    )

    #expect(resolved == CGSize(width: 2388, height: 1580))
}

@Test("Auto resolution can use a fullscreen viewport without safe area reduction")
func autoResolutionSupportsFullscreenViewportSizing() {
    let resolved = ShadowClientAutoResolutionPolicy.resolvePixelSize(
        displayLogicalSize: CGSize(width: 1366, height: 1024),
        safeAreaInsets: .init(),
        scale: 2.0
    )

    #expect(resolved == CGSize(width: 2732, height: 2048))
}

@Test("Auto resolution launch geometry keeps logical render size and exposes scale factor")
func autoResolutionLaunchGeometryPreservesLogicalSizeAndScaleFactor() {
    let geometry = ShadowClientAutoResolutionPolicy.resolveLaunchGeometry(
        displayLogicalSize: CGSize(width: 1194, height: 834),
        safeAreaInsets: .init(top: 24, leading: 0, bottom: 20, trailing: 0),
        scale: 2.0
    )

    #expect(geometry.renderSize == CGSize(width: 1194, height: 790))
    #expect(geometry.pixelSize == CGSize(width: 2388, height: 1580))
    #expect(geometry.scalePercent == 200)
}

@Test("Auto resolution launch geometry exposes physical 4K mode with independent scale factor")
func autoResolutionLaunchGeometryExposesPhysicalDisplayModeForRetina() {
    let geometry = ShadowClientAutoResolutionPolicy.resolveLaunchGeometry(
        displayLogicalSize: CGSize(width: 2560, height: 1440),
        safeAreaInsets: .init(),
        scale: 1.5
    )

    #expect(geometry.renderSize == CGSize(width: 2560, height: 1440))
    #expect(geometry.pixelSize == CGSize(width: 3840, height: 2160))
    #expect(geometry.scalePercent == 150)
}
