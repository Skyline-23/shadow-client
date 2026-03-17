#if !os(macOS)
import CoreGraphics

enum ShadowClientDisplayMetricsPlatformKit {
    static func displayPixelSizeForLaunch(
        from _: ShadowClientDisplayMetricsState
    ) -> CGSize? {
        nil
    }

    static func launchRequestSize(
        from geometry: ShadowClientAutoResolutionPolicy.LaunchGeometry
    ) -> CGSize {
        geometry.renderSize
    }

    static func launchRequestScalePercent(
        from geometry: ShadowClientAutoResolutionPolicy.LaunchGeometry
    ) -> Int {
        geometry.scalePercent
    }
}
#endif
