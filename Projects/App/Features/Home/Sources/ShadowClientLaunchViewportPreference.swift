import SwiftUI

struct ShadowClientLaunchViewportMetrics: Equatable {
    let logicalSize: CGSize
    let safeAreaInsets: EdgeInsets
}

struct ShadowClientLaunchViewportPreferenceKey: PreferenceKey {
    static var defaultValue: ShadowClientLaunchViewportMetrics = .init(
        logicalSize: .zero,
        safeAreaInsets: .init()
    )

    static func reduce(
        value: inout ShadowClientLaunchViewportMetrics,
        nextValue: () -> ShadowClientLaunchViewportMetrics
    ) {
        value = nextValue()
    }
}
