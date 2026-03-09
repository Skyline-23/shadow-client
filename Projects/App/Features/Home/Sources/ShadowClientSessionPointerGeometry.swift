import CoreGraphics

struct ShadowClientSessionAbsolutePointerState: Equatable {
    let x: Double
    let y: Double
    let referenceWidth: Double
    let referenceHeight: Double
}

enum ShadowClientSessionPointerGeometry {
    static func absolutePointerState(
        for location: CGPoint,
        containerBounds: CGRect,
        videoSize: CGSize?
    ) -> ShadowClientSessionAbsolutePointerState? {
        guard containerBounds.width > 0, containerBounds.height > 0 else {
            return nil
        }

        let fittedRect = fittedVideoRect(
            in: containerBounds,
            videoSize: videoSize
        )
        guard fittedRect.width >= 1, fittedRect.height >= 1 else {
            return nil
        }

        let clampedX = min(max(location.x, fittedRect.minX), fittedRect.maxX)
        let clampedY = min(max(location.y, fittedRect.minY), fittedRect.maxY)
        let relativeX = max(0, min(clampedX - fittedRect.minX, fittedRect.width - 1))
        let relativeY = max(0, min(clampedY - fittedRect.minY, fittedRect.height - 1))

        return ShadowClientSessionAbsolutePointerState(
            x: relativeX,
            y: relativeY,
            referenceWidth: fittedRect.width,
            referenceHeight: fittedRect.height
        )
    }

    private static func fittedVideoRect(
        in containerBounds: CGRect,
        videoSize: CGSize?
    ) -> CGRect {
        guard let videoSize,
              videoSize.width > 0,
              videoSize.height > 0
        else {
            return containerBounds
        }

        let scale = min(
            containerBounds.width / videoSize.width,
            containerBounds.height / videoSize.height
        )
        let fittedWidth = videoSize.width * scale
        let fittedHeight = videoSize.height * scale
        let originX = containerBounds.minX + (containerBounds.width - fittedWidth) * 0.5
        let originY = containerBounds.minY + (containerBounds.height - fittedHeight) * 0.5
        return CGRect(x: originX, y: originY, width: fittedWidth, height: fittedHeight)
    }
}
