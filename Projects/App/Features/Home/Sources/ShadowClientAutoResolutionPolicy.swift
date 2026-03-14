import CoreGraphics
import SwiftUI

enum ShadowClientAutoResolutionPolicy {
    struct LaunchGeometry: Equatable {
        let renderSize: CGSize
        let pixelSize: CGSize
        let scalePercent: Int
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

    private static func alignedPixelDimension(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded(.down))
        let evenAligned = rounded - (rounded % 2)
        return CGFloat(max(2, evenAligned))
    }
}
