#if !os(macOS)
import CoreGraphics

enum ShadowClientDisplayMetricsPlatformKit {
    static func launchRequestSize(
        from geometry: ShadowClientAutoResolutionPolicy.LaunchGeometry
    ) -> CGSize {
        geometry.renderSize
    }
}
#endif
