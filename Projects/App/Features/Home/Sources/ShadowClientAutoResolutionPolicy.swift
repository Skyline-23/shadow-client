import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

enum ShadowClientAutoResolutionPolicy {
    struct LaunchGeometry: Equatable {
        let renderSize: CGSize
        let pixelSize: CGSize
        let scalePercent: Int
    }

    @MainActor
    static func resolvePixelSize(
        logicalSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGSize {
        let metrics = effectiveDisplayMetrics(
            fallbackLogicalSize: logicalSize,
            fallbackSafeAreaInsets: safeAreaInsets
        )
        return resolvePixelSize(
            displayLogicalSize: metrics.logicalSize,
            safeAreaInsets: metrics.safeAreaInsets,
            scale: metrics.scale
        )
    }

    static func resolvePixelSize(
        displayLogicalSize: CGSize,
        safeAreaInsets: EdgeInsets,
        scale: CGFloat
    ) -> CGSize {
        let safeAreaWidth = max(
            1,
            displayLogicalSize.width - safeAreaInsets.leading - safeAreaInsets.trailing
        )
        let safeAreaHeight = max(
            1,
            displayLogicalSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
        let resolvedScale = max(1.0, scale)

        return CGSize(
            width: alignedPixelDimension(safeAreaWidth * resolvedScale),
            height: alignedPixelDimension(safeAreaHeight * resolvedScale)
        )
    }

    @MainActor
    static func resolveLaunchGeometry(
        logicalSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> LaunchGeometry {
        let metrics = effectiveDisplayMetrics(
            fallbackLogicalSize: logicalSize,
            fallbackSafeAreaInsets: safeAreaInsets
        )
        return resolveLaunchGeometry(
            displayLogicalSize: metrics.logicalSize,
            safeAreaInsets: metrics.safeAreaInsets,
            scale: metrics.scale
        )
    }

    static func resolveLaunchGeometry(
        displayLogicalSize: CGSize,
        safeAreaInsets: EdgeInsets,
        scale: CGFloat
    ) -> LaunchGeometry {
        let safeAreaWidth = max(
            1,
            displayLogicalSize.width - safeAreaInsets.leading - safeAreaInsets.trailing
        )
        let safeAreaHeight = max(
            1,
            displayLogicalSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
        let renderSize = CGSize(
            width: alignedPixelDimension(safeAreaWidth),
            height: alignedPixelDimension(safeAreaHeight)
        )
        let resolvedScale = max(1.0, scale)
        let pixelSize = CGSize(
            width: alignedPixelDimension(renderSize.width * resolvedScale),
            height: alignedPixelDimension(renderSize.height * resolvedScale)
        )

        return .init(
            renderSize: renderSize,
            pixelSize: pixelSize,
            scalePercent: max(100, Int((resolvedScale * 100).rounded()))
        )
    }

    @MainActor
    private static func effectiveDisplayMetrics(
        fallbackLogicalSize: CGSize,
        fallbackSafeAreaInsets: EdgeInsets
    ) -> (logicalSize: CGSize, safeAreaInsets: EdgeInsets, scale: CGFloat) {
        #if os(macOS)
        if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            return (
                logicalSize: screen.frame.size,
                safeAreaInsets: .init(),
                scale: screen.backingScaleFactor
            )
        }
        #elseif os(iOS) || os(tvOS)
        if let window = activeWindow() {
            return (
                logicalSize: window.bounds.size,
                safeAreaInsets: EdgeInsets(
                    top: window.safeAreaInsets.top,
                    leading: window.safeAreaInsets.left,
                    bottom: window.safeAreaInsets.bottom,
                    trailing: window.safeAreaInsets.right
                ),
                scale: window.screen.scale
            )
        }
        #endif

        return (
            logicalSize: fallbackLogicalSize,
            safeAreaInsets: fallbackSafeAreaInsets,
            scale: currentDisplayScale()
        )
    }

    @MainActor
    private static func currentDisplayScale() -> CGFloat {
        #if os(macOS)
        return NSApp.keyWindow?.screen?.backingScaleFactor ??
            NSScreen.main?.backingScaleFactor ??
            2.0
        #elseif os(iOS) || os(tvOS)
        return activeWindow()?.screen.scale ?? UIScreen.main.scale
        #else
        return 1.0
        #endif
    }

    #if os(iOS) || os(tvOS)
    @MainActor
    private static func activeWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
    #endif

    private static func alignedPixelDimension(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded(.down))
        let evenAligned = rounded - (rounded % 2)
        return CGFloat(max(2, evenAligned))
    }
}
