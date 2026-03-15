import CoreGraphics
import SwiftUI

public struct ShadowClientSessionPointerVisibleRegionsPreferenceKey: PreferenceKey {
    public static var defaultValue: [CGRect] = []

    public static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value = nextValue()
    }
}
