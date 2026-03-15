import CoreGraphics
import ShadowUIFoundation
import SwiftUI

struct ShadowClientDisplayMetricsState: Equatable {
    let scale: CGFloat
    let pixelSize: CGSize?
    let logicalSize: CGSize?
    let safeAreaInsets: EdgeInsets

    static let `default` = ShadowClientDisplayMetricsState(
        scale: 1.0,
        pixelSize: nil,
        logicalSize: nil,
        safeAreaInsets: .init()
    )
}

enum ShadowClientDisplayMetricsKit {
    static func resolveLaunchGeometry(
        viewportMetrics: ShadowClientLaunchViewportMetrics,
        displayMetrics: ShadowClientDisplayMetricsState
    ) -> ShadowClientAutoResolutionPolicy.LaunchGeometry {
        let resolvedLogicalSize: CGSize
        if viewportMetrics.logicalSize.width > 1, viewportMetrics.logicalSize.height > 1 {
            resolvedLogicalSize = viewportMetrics.logicalSize
        } else {
            resolvedLogicalSize = displayMetrics.logicalSize ?? viewportMetrics.logicalSize
        }

        let resolvedSafeAreaInsets: EdgeInsets
        if resolvedLogicalSize == viewportMetrics.logicalSize {
            resolvedSafeAreaInsets = viewportMetrics.safeAreaInsets
        } else {
            resolvedSafeAreaInsets = displayMetrics.safeAreaInsets
        }

        return ShadowClientAutoResolutionPolicy.resolveLaunchGeometry(
            displayLogicalSize: resolvedLogicalSize,
            safeAreaInsets: resolvedSafeAreaInsets,
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
