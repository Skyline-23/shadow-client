import Testing
#if os(iOS)
import UIKit
#endif
@testable import ShadowClientFeatureHome

#if os(iOS)
@Test("Indirect pointer touches bypass touch gesture recognizers")
func indirectPointerTouchesBypassGestureRecognizers() {
    #expect(
        ShadowClientIOSIndirectPointerInputPolicy.shouldHandleDirectly(.indirectPointer)
    )
    #expect(
        !ShadowClientIOSIndirectPointerInputPolicy.shouldAllowGestureRecognition(
            for: .indirectPointer
        )
    )
    #expect(
        ShadowClientIOSIndirectPointerInputPolicy.shouldAllowGestureRecognition(
            for: .direct
        )
    )
}
#endif
