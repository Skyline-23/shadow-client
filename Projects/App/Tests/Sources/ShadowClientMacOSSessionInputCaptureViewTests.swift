#if os(macOS)
import CoreGraphics
import Testing
@testable import ShadowClientFeatureHome
@testable import ShadowUIFoundation

@Test("macOS input capture emits relative pointer movement while pointer capture is active")
func macOSInputCaptureUsesRelativePointerMotionWhenCaptured() {
    let motion = ShadowClientMacOSPointerInputPolicy.motionEvent(
        locationInView: CGPoint(x: 140, y: 120),
        previousLocationInView: CGPoint(x: 100, y: 150),
        containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
        videoSize: CGSize(width: 1920, height: 1080),
        isCaptured: true
    )

    #expect(motion == .pointerMoved(x: 40, y: 30))
}

@Test("macOS input capture emits absolute pointer position while pointer remains visible")
func macOSInputCaptureUsesAbsolutePointerPositionWhenNotCaptured() {
    let motion = ShadowClientMacOSPointerInputPolicy.motionEvent(
        locationInView: CGPoint(x: 150, y: 80),
        previousLocationInView: CGPoint(x: 120, y: 90),
        containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
        videoSize: CGSize(width: 1920, height: 1080),
        isCaptured: false
    )

    #expect(
        motion == .pointerPosition(
            x: 960,
            y: 540,
            referenceWidth: 1920,
            referenceHeight: 1080
        )
    )
}

@Test("macOS input capture avoids absolute pointer sync for button events while captured")
func macOSInputCaptureDoesNotSyncAbsolutePointerForCapturedButtons() {
    #expect(!ShadowClientMacOSPointerInputPolicy.shouldSyncAbsolutePointerBeforeButton(isCaptured: true))
    #expect(ShadowClientMacOSPointerInputPolicy.shouldSyncAbsolutePointerBeforeButton(isCaptured: false))
}
#endif
