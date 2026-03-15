#if os(macOS)
import CoreGraphics

enum ShadowClientDisplayMetricsPlatformKit {
    static func launchRequestSize(
        from geometry: ShadowClientAutoResolutionPolicy.LaunchGeometry
    ) -> CGSize {
        geometry.pixelSize
    }

    static func launchRequestScalePercent(
        from geometry: ShadowClientAutoResolutionPolicy.LaunchGeometry
    ) -> Int {
        geometry.scalePercent
    }
}
#endif
