import SwiftUI

public struct ShadowClientLaunchViewportMetrics: Equatable {
    public let logicalSize: CGSize
    public let safeAreaInsets: EdgeInsets

    public init(logicalSize: CGSize, safeAreaInsets: EdgeInsets) {
        self.logicalSize = logicalSize
        self.safeAreaInsets = safeAreaInsets
    }
}

public struct ShadowClientLaunchViewportPreferenceKey: PreferenceKey {
    public static var defaultValue: ShadowClientLaunchViewportMetrics = .init(
        logicalSize: .zero,
        safeAreaInsets: .init()
    )

    public static func reduce(
        value: inout ShadowClientLaunchViewportMetrics,
        nextValue: () -> ShadowClientLaunchViewportMetrics
    ) {
        value = nextValue()
    }
}
