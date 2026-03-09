import CoreGraphics
import SwiftUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Auto resolution uses display-sized metrics instead of a smaller viewport")
func autoResolutionPrefersDisplayMetrics() {
    let resolved = ShadowClientAutoResolutionPolicy.resolvePixelSize(
        displayLogicalSize: CGSize(width: 1728, height: 1117),
        safeAreaInsets: .init(),
        scale: 2.0
    )

    #expect(resolved == CGSize(width: 3456, height: 2234))
}

@Test("Auto resolution subtracts safe area before scaling")
func autoResolutionSubtractsSafeAreaBeforeScaling() {
    let resolved = ShadowClientAutoResolutionPolicy.resolvePixelSize(
        displayLogicalSize: CGSize(width: 1194, height: 834),
        safeAreaInsets: .init(top: 24, leading: 0, bottom: 20, trailing: 0),
        scale: 2.0
    )

    #expect(resolved == CGSize(width: 2388, height: 1580))
}
