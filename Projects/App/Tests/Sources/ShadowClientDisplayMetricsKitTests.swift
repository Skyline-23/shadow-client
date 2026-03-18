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
            logicalSize: CGSize(width: 1194, height: 834),
            safeAreaInsets: .init()
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
            logicalSize: CGSize(width: 1194, height: 834),
            safeAreaInsets: .init()
        )
    )

    #expect(geometry.renderSize == CGSize(width: 820, height: 1136))
    #expect(geometry.pixelSize == CGSize(width: 1640, height: 2272))
    #expect(geometry.scalePercent == 200)
}

@Test("Retina auto launch settings keep logical render size and expose scale intent")
func retinaAutoLaunchSettingsExposeScaleIntent() {
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
            logicalSize: CGSize(width: 1048, height: 970),
            safeAreaInsets: .init(top: 24, leading: 0, bottom: 20, trailing: 0)
        )
    )

    #expect(settings.width == 1048)
    #expect(settings.height == 970)
    #expect(settings.resolutionScalePercent == 200)
    #expect(settings.requestHiDPI)
}

@Test("Retina auto launch settings keep logical macOS render size instead of physical mode")
func retinaAutoLaunchSettingsKeepLogicalMacOSRenderSize() {
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
        viewportMetrics: .init(logicalSize: CGSize(width: 1728, height: 1117), safeAreaInsets: .init()),
        displayMetrics: .init(
            scale: 2.0,
            pixelSize: CGSize(width: 3456, height: 2234),
            logicalSize: CGSize(width: 1728, height: 1117),
            safeAreaInsets: .init()
        )
    )

    #expect(settings.width == 1728)
    #expect(settings.height == 1116)
    #expect(settings.resolutionScalePercent == 200)
    #expect(settings.requestHiDPI)
}

@Test("Display metrics kit preserves fallback safe area insets when the viewport has not been laid out yet")
func displayMetricsKitPreservesFallbackSafeAreaInsets() {
    let geometry = ShadowClientDisplayMetricsKit.resolveLaunchGeometry(
        viewportMetrics: .init(logicalSize: .zero, safeAreaInsets: .init()),
        displayMetrics: .init(
            scale: 2.0,
            pixelSize: CGSize(width: 2388, height: 1668),
            logicalSize: CGSize(width: 1194, height: 834),
            safeAreaInsets: .init(top: 24, leading: 0, bottom: 20, trailing: 0)
        )
    )

    #expect(geometry.renderSize == CGSize(width: 1194, height: 790))
    #expect(geometry.pixelSize == CGSize(width: 2388, height: 1580))
}
