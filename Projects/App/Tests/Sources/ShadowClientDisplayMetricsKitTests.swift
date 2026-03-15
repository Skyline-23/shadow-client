import CoreGraphics
import SwiftUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Display metrics kit falls back to display logical size when viewport has not been laid out yet")
func displayMetricsKitFallsBackToDisplayLogicalSizeForZeroViewport() {
    let geometry = ShadowClientDisplayMetricsKit.resolveLaunchGeometry(
        viewportMetrics: .init(logicalSize: .zero, safeAreaInsets: .init()),
        displayMetrics: .init(
            scale: 2.0,
            pixelSize: CGSize(width: 2388, height: 1668),
            logicalSize: CGSize(width: 1194, height: 834)
        )
    )

    #expect(geometry.renderSize == CGSize(width: 1194, height: 834))
    #expect(geometry.pixelSize == CGSize(width: 2388, height: 1668))
    #expect(geometry.scalePercent == 200)
}

@Test("Display metrics kit keeps the active viewport when it is already available")
func displayMetricsKitPrefersViewportMetricsWhenAvailable() {
    let geometry = ShadowClientDisplayMetricsKit.resolveLaunchGeometry(
        viewportMetrics: .init(
            logicalSize: CGSize(width: 820, height: 1180),
            safeAreaInsets: .init(top: 24, leading: 0, bottom: 20, trailing: 0)
        ),
        displayMetrics: .init(
            scale: 2.0,
            pixelSize: CGSize(width: 1640, height: 2360),
            logicalSize: CGSize(width: 1194, height: 834)
        )
    )

    #expect(geometry.renderSize == CGSize(width: 820, height: 1136))
    #expect(geometry.pixelSize == CGSize(width: 1640, height: 2360))
    #expect(geometry.scalePercent == 200)
}

@Test("Retina auto launch settings use pixel size without a second iOS scale factor")
func retinaAutoLaunchSettingsUsePixelSizeWithoutExtraScaleFactor() {
    let settings = ShadowClientLaunchSettingsKit.resolvedLaunchSettings(
        currentSettings: ShadowClientAppSettings(
            resolution: .retinaAuto,
            frameRate: .fps60,
            bitrateKbps: 18_000
        ),
        selectedResolution: .retinaAuto,
        hostApp: nil,
        networkSignal: nil,
        localHDRDisplayAvailable: false,
        viewportMetrics: .init(logicalSize: CGSize(width: 1048, height: 970), safeAreaInsets: .init()),
        displayMetrics: .init(
            scale: 2.0,
            pixelSize: CGSize(width: 2096, height: 1940),
            logicalSize: CGSize(width: 1048, height: 970)
        )
    )

    #expect(settings.width == 2096)
    #expect(settings.height == 1940)
    #expect(settings.resolutionScalePercent == 100)
}
