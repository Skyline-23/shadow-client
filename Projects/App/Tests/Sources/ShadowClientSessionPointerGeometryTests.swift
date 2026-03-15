import CoreGraphics
import Testing
@testable import ShadowUIFoundation

@Test("Absolute pointer geometry maps fitted view coordinates into source video coordinates")
func absolutePointerGeometryMapsIntoSourceVideoCoordinates() {
    let state = ShadowClientSessionPointerGeometry.absolutePointerState(
        for: CGPoint(x: 150, y: 80),
        containerBounds: CGRect(x: 0, y: 0, width: 300, height: 200),
        videoSize: CGSize(width: 1920, height: 1080)
    )

    #expect(state != nil)
    #expect(state?.referenceWidth == 1920)
    #expect(state?.referenceHeight == 1080)
    #expect(state?.x == 960)
    #expect(state?.y == 540)
}
