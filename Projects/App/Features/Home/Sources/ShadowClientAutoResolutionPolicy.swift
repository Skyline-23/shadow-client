import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

enum ShadowClientAutoResolutionPolicy {
    private struct DisplayMetrics {
        let logicalSize: CGSize
        let safeAreaInsets: EdgeInsets
        let scale: CGFloat
        let pixelSize: CGSize?
    }

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
            scale: metrics.scale,
            displayPixelSize: metrics.pixelSize
        )
    }

    static func resolveLaunchGeometry(
        displayLogicalSize: CGSize,
        safeAreaInsets: EdgeInsets,
        scale: CGFloat,
        displayPixelSize: CGSize? = nil
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
        let resolvedPixelSize = displayPixelSize.map {
            CGSize(
                width: alignedPixelDimension($0.width),
                height: alignedPixelDimension($0.height)
            )
        } ?? CGSize(
            width: alignedPixelDimension(renderSize.width * resolvedScale),
            height: alignedPixelDimension(renderSize.height * resolvedScale)
        )
        let effectiveScale = max(
            1.0,
            resolvedPixelSize.width / max(1.0, renderSize.width)
        )

        return .init(
            renderSize: renderSize,
            pixelSize: resolvedPixelSize,
            scalePercent: max(100, Int((effectiveScale * 100).rounded()))
        )
    }

    @MainActor
    private static func effectiveDisplayMetrics(
        fallbackLogicalSize: CGSize,
        fallbackSafeAreaInsets: EdgeInsets
    ) -> DisplayMetrics {
        #if os(macOS)
        if let screen = NSApp.keyWindow?.screen ?? NSScreen.main {
            return .init(
                logicalSize: screen.frame.size,
                safeAreaInsets: .init(),
                scale: screen.backingScaleFactor,
                pixelSize: currentDisplayModePixelSize(for: screen)
            )
        }
        #elseif os(iOS) || os(tvOS)
        if let window = activeWindow() {
            return .init(
                logicalSize: window.bounds.size,
                safeAreaInsets: EdgeInsets(
                    top: window.safeAreaInsets.top,
                    leading: window.safeAreaInsets.left,
                    bottom: window.safeAreaInsets.bottom,
                    trailing: window.safeAreaInsets.right
                ),
                scale: window.screen.scale,
                pixelSize: nil
            )
        }
        #endif

        return .init(
            logicalSize: fallbackLogicalSize,
            safeAreaInsets: fallbackSafeAreaInsets,
            scale: currentDisplayScale(),
            pixelSize: nil
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

    #if os(macOS)
    @MainActor
    private static func currentDisplayModePixelSize(for screen: NSScreen) -> CGSize? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let mode = CGDisplayCopyDisplayMode(displayID) else {
            return nil
        }
        return CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
    }
    #endif

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
