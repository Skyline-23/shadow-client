import CoreGraphics
import SwiftUI

struct ShadowClientSessionPointerVisibleRegionsPreferenceKey: PreferenceKey {
    static var defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value = nextValue()
    }
}
