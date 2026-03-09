import CoreGraphics
import SwiftUI

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

enum ShadowClientAutoResolutionPolicy {
    @MainActor
    static func resolvePixelSize(
        logicalSize: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> CGSize {
        let safeAreaWidth = max(
            1,
            logicalSize.width - safeAreaInsets.leading - safeAreaInsets.trailing
        )
        let safeAreaHeight = max(
            1,
            logicalSize.height - safeAreaInsets.top - safeAreaInsets.bottom
        )
        let scale = max(1.0, currentDisplayScale())

        return CGSize(
            width: alignedPixelDimension(safeAreaWidth * scale),
            height: alignedPixelDimension(safeAreaHeight * scale)
        )
    }

    @MainActor
    private static func currentDisplayScale() -> CGFloat {
        #if os(macOS)
        return NSApp.keyWindow?.screen?.backingScaleFactor ??
            NSScreen.main?.backingScaleFactor ??
            2.0
        #elseif os(iOS) || os(tvOS)
        return UIScreen.main.scale
        #else
        return 1.0
        #endif
    }

    private static func alignedPixelDimension(_ value: CGFloat) -> CGFloat {
        let rounded = Int(value.rounded(.down))
        let evenAligned = rounded - (rounded % 2)
        return CGFloat(max(2, evenAligned))
    }
}
