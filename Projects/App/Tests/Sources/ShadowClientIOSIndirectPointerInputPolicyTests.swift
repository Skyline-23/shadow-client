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
            for: .indirectPointer,
            recognizer: UIPanGestureRecognizer()
        )
    )
    #expect(
        ShadowClientIOSIndirectPointerInputPolicy.shouldAllowGestureRecognition(
            for: .indirectPointer,
            recognizer: UIHoverGestureRecognizer()
        )
    )
    #expect(
        ShadowClientIOSIndirectPointerInputPolicy.shouldAllowGestureRecognition(
            for: .direct,
            recognizer: UIPanGestureRecognizer()
        )
    )
}

@Test("Indirect pointer touch end releases held primary button")
func indirectPointerTouchEndReleasesHeldPrimaryButton() {
    let transition = ShadowClientIOSIndirectPointerTouchTransition.make(
        for: .ended,
        isPrimaryButtonHeld: true
    )

    #expect(transition.shouldEmitAbsolutePosition)
    #expect(
        transition.buttonEvent == .pointerButton(button: .left, isPressed: false)
    )
    #expect(!transition.nextPrimaryButtonHeld)
    #expect(!transition.capturesDragLocation)
}

@Test("Indirect pointer touch begin only emits primary down once")
func indirectPointerTouchBeginDoesNotDuplicatePrimaryDown() {
    let transition = ShadowClientIOSIndirectPointerTouchTransition.make(
        for: .began,
        isPrimaryButtonHeld: true
    )

    #expect(transition.shouldRequestFocus)
    #expect(transition.shouldEmitAbsolutePosition)
    #expect(transition.buttonEvent == nil)
    #expect(transition.nextPrimaryButtonHeld)
    #expect(transition.capturesDragLocation)
}
#endif
