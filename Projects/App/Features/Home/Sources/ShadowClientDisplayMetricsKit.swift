import CoreGraphics
import ShadowUIFoundation
import SwiftUI

struct ShadowClientDisplayMetricsState: Equatable {
    let scale: CGFloat
    let pixelSize: CGSize?

    static let `default` = ShadowClientDisplayMetricsState(
        scale: 1.0,
        pixelSize: nil
    )
}

enum ShadowClientDisplayMetricsKit {
    static func resolveLaunchGeometry(
        viewportMetrics: ShadowClientLaunchViewportMetrics,
        displayMetrics: ShadowClientDisplayMetricsState
    ) -> ShadowClientAutoResolutionPolicy.LaunchGeometry {
        ShadowClientAutoResolutionPolicy.resolveLaunchGeometry(
            displayLogicalSize: viewportMetrics.logicalSize,
            safeAreaInsets: viewportMetrics.safeAreaInsets,
            scale: max(1.0, displayMetrics.scale),
            displayPixelSize: displayMetrics.pixelSize
        )
    }

    static func resolvePixelSize(
        viewportMetrics: ShadowClientLaunchViewportMetrics,
        displayMetrics: ShadowClientDisplayMetricsState
    ) -> CGSize {
        let geometry = resolveLaunchGeometry(
            viewportMetrics: viewportMetrics,
            displayMetrics: displayMetrics
        )
        return ShadowClientDisplayMetricsPlatformKit.launchRequestSize(
            from: geometry
        )
    }
}
