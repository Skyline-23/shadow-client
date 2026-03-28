import CoreGraphics
import CoreVideo
import Metal

enum ShadowClientRealtimeSessionHDRCompositor {
    struct SinkCapabilities: Equatable, Sendable {
        let supportsFrameGatedHDR: Bool
        let supportsHDRTileOverlay: Bool
        let supportsPerFrameHDRMetadata: Bool
    }

    static func allowsExtendedDynamicRange(
        dynamicRangeMode: ShadowClientRealtimeSessionSurfaceContext.DynamicRangeMode,
        hdrFrameState: ShadowClientHDRFrameState?
    ) -> Bool {
        guard dynamicRangeMode == .hdr else {
            return false
        }
        guard let hdrFrameState else {
            return true
        }

        switch hdrFrameState.content {
        case .sdr:
            return false
        case .fullFrameHDR:
            return true
        case .partialHDROverlay:
            return !hdrFrameState.overlayRegions.isEmpty
        }
    }

    static func sinkCapabilities(
        potentialEDRHeadroom: Float,
        hasMetalRenderer: Bool
    ) -> SinkCapabilities {
        let supportsFrameGatedHDR = potentialEDRHeadroom > 1.0 && hasMetalRenderer
        let supportsPartialHDROverlay = supportsFrameGatedHDR

        return .init(
            supportsFrameGatedHDR: supportsFrameGatedHDR,
            supportsHDRTileOverlay: supportsPartialHDROverlay,
            supportsPerFrameHDRMetadata: supportsPartialHDROverlay
        )
    }

    static func render(
        snapshot: ShadowClientRealtimeSessionFrameStore.Snapshot,
        pixelBuffer: CVPixelBuffer,
        into baseRenderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        drawableSize: CGSize,
        colorPixelFormat: MTLPixelFormat,
        renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration,
        yuvPipeline: ShadowClientRealtimeSessionYUVMetalPipeline,
        currentEDRHeadroom: Float?
    ) -> Bool {
        guard let hdrFrameState = snapshot.hdrFrameState,
              hdrFrameState.content == .partialHDROverlay,
              !hdrFrameState.overlayRegions.isEmpty
        else {
            return yuvPipeline.render(
                pixelBuffer: pixelBuffer,
                into: baseRenderPassDescriptor,
                commandBuffer: commandBuffer,
                drawableSize: drawableSize,
                colorPixelFormat: colorPixelFormat,
                outputColorSpace: renderTargetConfiguration.outputColorSpace,
                prefersExtendedDynamicRange: renderTargetConfiguration.prefersExtendedDynamicRange,
                currentEDRHeadroom: currentEDRHeadroom
            )
        }

        let didRenderBase = yuvPipeline.render(
            pixelBuffer: pixelBuffer,
            into: baseRenderPassDescriptor,
            commandBuffer: commandBuffer,
            drawableSize: drawableSize,
            colorPixelFormat: colorPixelFormat,
            outputColorSpace: renderTargetConfiguration.outputColorSpace,
            prefersExtendedDynamicRange: renderTargetConfiguration.prefersExtendedDynamicRange,
            currentEDRHeadroom: currentEDRHeadroom,
            renderIntent: .sdrBaseForHDROverlay
        )
        guard didRenderBase else {
            return false
        }

        guard renderTargetConfiguration.prefersExtendedDynamicRange else {
            return true
        }

        let videoSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        for overlayRegion in hdrFrameState.overlayRegions {
            guard let scissorRect = ShadowClientRealtimeSessionYUVMetalPipeline.drawableScissorRect(
                for: overlayRegion,
                videoSize: videoSize,
                drawableSize: drawableSize
            ),
            let overlayRenderPassDescriptor = overlayRenderPassDescriptor(
                from: baseRenderPassDescriptor
            ) else {
                continue
            }

            let didRenderOverlay = yuvPipeline.render(
                pixelBuffer: pixelBuffer,
                into: overlayRenderPassDescriptor,
                commandBuffer: commandBuffer,
                drawableSize: drawableSize,
                colorPixelFormat: colorPixelFormat,
                outputColorSpace: renderTargetConfiguration.outputColorSpace,
                prefersExtendedDynamicRange: renderTargetConfiguration.prefersExtendedDynamicRange,
                currentEDRHeadroom: currentEDRHeadroom,
                scissorRect: scissorRect
            )
            guard didRenderOverlay else {
                return false
            }
        }

        return true
    }

    private static func overlayRenderPassDescriptor(
        from baseRenderPassDescriptor: MTLRenderPassDescriptor
    ) -> MTLRenderPassDescriptor? {
        guard let overlayRenderPassDescriptor =
            baseRenderPassDescriptor.copy() as? MTLRenderPassDescriptor
        else {
            return nil
        }

        overlayRenderPassDescriptor.colorAttachments[0].loadAction = .load
        return overlayRenderPassDescriptor
    }
}
