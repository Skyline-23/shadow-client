import CoreGraphics

public struct ShadowClientSessionAbsolutePointerState: Equatable {
    public let x: Double
    public let y: Double
    public let referenceWidth: Double
    public let referenceHeight: Double
}

public enum ShadowClientSessionPointerGeometry {
    public static func absolutePointerState(
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
        let referenceSize = normalizedReferenceVideoSize(videoSize, fallback: fittedRect.size)
        let widthScale = referenceSize.width / max(fittedRect.width, 1)
        let heightScale = referenceSize.height / max(fittedRect.height, 1)
        let normalizedX = min(max(relativeX * widthScale, 0), max(referenceSize.width - 1, 0))
        let normalizedY = min(max(relativeY * heightScale, 0), max(referenceSize.height - 1, 0))

        return ShadowClientSessionAbsolutePointerState(
            x: normalizedX,
            y: normalizedY,
            referenceWidth: referenceSize.width,
            referenceHeight: referenceSize.height
        )
    }

    public static func relativePointerDelta(
        from previousLocation: CGPoint,
        to location: CGPoint,
        containerBounds: CGRect,
        videoSize: CGSize?
    ) -> CGSize? {
        guard let previousState = absolutePointerState(
            for: previousLocation,
            containerBounds: containerBounds,
            videoSize: videoSize
        ),
        let currentState = absolutePointerState(
            for: location,
            containerBounds: containerBounds,
            videoSize: videoSize
        )
        else {
            return nil
        }

        let deltaX = currentState.x - previousState.x
        let deltaY = currentState.y - previousState.y
        guard deltaX != 0 || deltaY != 0 else {
            return nil
        }

        return CGSize(width: deltaX, height: deltaY)
    }

    private static func normalizedReferenceVideoSize(
        _ videoSize: CGSize?,
        fallback: CGSize
    ) -> CGSize {
        guard let videoSize,
              videoSize.width > 0,
              videoSize.height > 0
        else {
            return fallback
        }

        return videoSize
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
