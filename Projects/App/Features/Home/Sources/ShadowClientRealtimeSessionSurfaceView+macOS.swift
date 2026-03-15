import SwiftUI

#if os(macOS)
import AppKit
import CoreImage
import CoreVideo
import Foundation
import MetalKit
import os

struct ShadowClientRealtimeSessionSurfaceRepresentable: NSViewRepresentable {
    let surfaceContext: ShadowClientRealtimeSessionSurfaceContext

    final class Coordinator {
        var renderer: ShadowClientRealtimeSessionMetalRenderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = ShadowClientRealtimeSessionMetalRenderer(
                device: device,
                surfaceContext: surfaceContext
              )
        else {
            let fallback = NSView()
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = NSColor.black.cgColor
            return fallback
        }

        let view = MTKView(frame: .zero, device: device)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.colorspace = ShadowClientRealtimeSessionColorPipeline.defaultDisplayColorSpace
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = surfaceContext.preferredRenderFPS
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? MTKView {
            view.isPaused = false
            if view.preferredFramesPerSecond != surfaceContext.preferredRenderFPS {
                view.preferredFramesPerSecond = surfaceContext.preferredRenderFPS
            }
        } else {
            nsView.wantsLayer = true
            nsView.layer?.backgroundColor = NSColor.black.cgColor
        }
    }
}

@MainActor
final class ShadowClientRealtimeSessionMetalRenderer: NSObject, MTKViewDelegate {
    private let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "SurfaceView.macOS"
    )
    private let surfaceContext: ShadowClientRealtimeSessionSurfaceContext
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let yuvPipeline: ShadowClientRealtimeSessionYUVMetalPipeline?
    private var frameStreamTask: Task<Void, Never>?
    private var latestSnapshot = ShadowClientRealtimeSessionFrameStore.Snapshot(
        pixelBuffer: nil,
        revision: 0
    )
    private var cachedSourceRect: CGRect = .null
    private var cachedDrawableRect: CGRect = .null
    private var cachedTransform: CGAffineTransform = .identity
    private var lastRenderedFrameRevision: UInt64 = .max
    private var lastRenderedDrawableSize: CGSize = .zero
    private var hasLoggedRenderPathForCurrentSession = false

    init?(
        device: MTLDevice,
        surfaceContext: ShadowClientRealtimeSessionSurfaceContext
    ) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.surfaceContext = surfaceContext
        self.frameStore = surfaceContext.frameStore
        self.commandQueue = commandQueue
        self.yuvPipeline = ShadowClientRealtimeSessionYUVMetalPipeline(
            device: device
        )
        self.ciContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: [
                .cacheIntermediates: false,
                .useSoftwareRenderer: false,
            ]
        )
        super.init()
        frameStreamTask = Task { [weak self] in
            guard let self else {
                return
            }
            let stream = await frameStore.snapshotStream()
            for await snapshot in stream {
                self.latestSnapshot = snapshot
            }
        }
    }

    deinit {
        frameStreamTask?.cancel()
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        let snapshot = latestSnapshot
        let drawableSize = view.drawableSize
        if snapshot.revision == lastRenderedFrameRevision,
           drawableSize == lastRenderedDrawableSize
        {
            return
        }

        let pixelBuffer = snapshot.pixelBuffer?.value
        if pixelBuffer == nil {
            hasLoggedRenderPathForCurrentSession = false
        }
        let colorConfiguration = pixelBuffer.map {
            ShadowClientRealtimeSessionColorPipeline.configuration(
                for: $0,
                allowExtendedDynamicRange: surfaceContext.activeDynamicRangeMode == .hdr
            )
        }

        let canUseMetalYUV = pixelBuffer != nil && yuvPipeline?.canRender(pixelBuffer!) == true

        if let colorConfiguration, let pixelBuffer {
            let supportsExtendedDynamicRange = supportsExtendedDynamicRangeDisplay(for: view)
            applyColorConfiguration(
                colorConfiguration,
                to: view,
                supportsExtendedDynamicRange: supportsExtendedDynamicRange,
                renderBackend: canUseMetalYUV ? .metalYUV : .coreImage
            )
            _ = pixelBuffer
        }

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        if let pixelBuffer,
           let renderPass = view.currentRenderPassDescriptor,
           let yuvPipeline,
           yuvPipeline.canRender(pixelBuffer)
        {
            if !hasLoggedRenderPathForCurrentSession {
                logger.notice("Surface render path=metal-yuv pixel-format=0x\(String(CVPixelBufferGetPixelFormatType(pixelBuffer), radix: 16), privacy: .public)")
                hasLoggedRenderPathForCurrentSession = true
            }
            let didRender = yuvPipeline.render(
                pixelBuffer: pixelBuffer,
                into: renderPass,
                commandBuffer: commandBuffer,
                drawableSize: drawableSize,
                colorPixelFormat: view.colorPixelFormat
            )
            if didRender {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                surfaceContext.recordPresentedVideoFrame()
                lastRenderedFrameRevision = snapshot.revision
                lastRenderedDrawableSize = drawableSize
                return
            }
            logger.error("Surface render path=metal-yuv failed; falling back to CI")
            if let colorConfiguration {
                applyColorConfiguration(
                    colorConfiguration,
                    to: view,
                    supportsExtendedDynamicRange: supportsExtendedDynamicRangeDisplay(for: view),
                    renderBackend: .coreImage
                )
            }
        }

        if let pixelBuffer, let colorConfiguration {
            if !hasLoggedRenderPathForCurrentSession {
                logger.notice("Surface render path=core-image pixel-format=0x\(String(CVPixelBufferGetPixelFormatType(pixelBuffer), radix: 16), privacy: .public)")
                hasLoggedRenderPathForCurrentSession = true
            }
            let supportsExtendedDynamicRange = supportsExtendedDynamicRangeDisplay(for: view)
            let shouldToneMapHDRToSDR =
                colorConfiguration.prefersExtendedDynamicRange && !supportsExtendedDynamicRange

            let sourceOptions = ciSourceOptions(
                for: pixelBuffer,
                renderColorSpace: colorConfiguration.renderColorSpace
            )
            var sourceImage = CIImage(
                cvPixelBuffer: pixelBuffer,
                options: sourceOptions
            )
            if shouldToneMapHDRToSDR {
                sourceImage = toneMapHDRToSDRSoftwareFallback(sourceImage)
            }
            let outputColorSpace = resolvedDisplayColorSpace(
                for: view,
                prefersExtendedDynamicRange: colorConfiguration.prefersExtendedDynamicRange && !shouldToneMapHDRToSDR,
                sdrSourceColorSpace: colorConfiguration.renderColorSpace,
                hdrDisplayColorSpace: colorConfiguration.displayColorSpace
            )
            let drawableRect = CGRect(origin: .zero, size: drawableSize)
            let sourceRect = sourceImage.extent
            let transformed = sourceImage.transformed(
                by: transformForRendering(
                    sourceRect: sourceRect,
                    drawableRect: drawableRect
                )
            )

            ciContext.render(
                transformed,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: drawableRect,
                colorSpace: outputColorSpace
            )
        } else if let renderPass = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        {
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
        if pixelBuffer != nil {
            surfaceContext.recordPresentedVideoFrame()
        }
        lastRenderedFrameRevision = snapshot.revision
        lastRenderedDrawableSize = drawableSize
    }

    private func transformForRendering(
        sourceRect: CGRect,
        drawableRect: CGRect
    ) -> CGAffineTransform {
        if sourceRect.equalTo(cachedSourceRect), drawableRect.equalTo(cachedDrawableRect) {
            return cachedTransform
        }

        let scale = min(
            drawableRect.width / max(sourceRect.width, 1),
            drawableRect.height / max(sourceRect.height, 1)
        )
        let scaledSize = CGSize(
            width: sourceRect.width * scale,
            height: sourceRect.height * scale
        )
        let offset = CGPoint(
            x: (drawableRect.width - scaledSize.width) * 0.5,
            y: (drawableRect.height - scaledSize.height) * 0.5
        )

        cachedSourceRect = sourceRect
        cachedDrawableRect = drawableRect
        cachedTransform = CGAffineTransform(scaleX: scale, y: scale)
            .translatedBy(x: offset.x / max(scale, 0.0001), y: offset.y / max(scale, 0.0001))
        return cachedTransform
    }

    private func applyColorConfiguration(
        _ configuration: ShadowClientRealtimeSessionColorConfiguration,
        to view: MTKView,
        supportsExtendedDynamicRange: Bool,
        renderBackend: ShadowClientSurfaceColorRenderBackend
    ) {
        let shouldRenderExtendedDynamicRange =
            configuration.prefersExtendedDynamicRange && supportsExtendedDynamicRange

        let targetPixelFormat: MTLPixelFormat = shouldRenderExtendedDynamicRange
            ? configuration.pixelFormat
            : .bgra8Unorm
        if view.colorPixelFormat != targetPixelFormat {
            view.colorPixelFormat = targetPixelFormat
        }
        view.colorspace = resolvedDisplayColorSpace(
            for: view,
            prefersExtendedDynamicRange: shouldRenderExtendedDynamicRange,
            sdrSourceColorSpace: configuration.renderColorSpace,
            hdrDisplayColorSpace: configuration.displayColorSpace,
            hdrSourceColorSpace: configuration.renderColorSpace,
            renderBackend: renderBackend
        )

        if #available(macOS 10.15, *),
           let metalLayer = view.layer as? CAMetalLayer
        {
            metalLayer.colorspace = resolvedDisplayColorSpace(
                for: view,
                prefersExtendedDynamicRange: shouldRenderExtendedDynamicRange,
                sdrSourceColorSpace: configuration.renderColorSpace,
                hdrDisplayColorSpace: configuration.displayColorSpace,
                hdrSourceColorSpace: configuration.renderColorSpace,
                renderBackend: renderBackend
            )
            metalLayer.wantsExtendedDynamicRangeContent = shouldRenderExtendedDynamicRange
        }
    }

    private func supportsExtendedDynamicRangeDisplay(for view: MTKView) -> Bool {
        guard #available(macOS 10.15, *) else {
            return false
        }
        let screen = view.window?.screen ?? NSScreen.main
        let potentialHeadroom = screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        return potentialHeadroom > 1.0
    }

    private func resolvedDisplayColorSpace(
        for view: MTKView,
        prefersExtendedDynamicRange: Bool,
        sdrSourceColorSpace: CGColorSpace,
        hdrDisplayColorSpace: CGColorSpace,
        hdrSourceColorSpace: CGColorSpace? = nil,
        renderBackend: ShadowClientSurfaceColorRenderBackend = .coreImage
    ) -> CGColorSpace {
        ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
            prefersExtendedDynamicRange: prefersExtendedDynamicRange,
            sdrSourceColorSpace: sdrSourceColorSpace,
            hdrDisplayColorSpace: hdrDisplayColorSpace,
            screenColorSpace: (view.window?.screen ?? NSScreen.main)?.colorSpace?.cgColorSpace,
            hdrSourceColorSpace: hdrSourceColorSpace,
            renderBackend: renderBackend
        )
    }

    private func ciSourceOptions(
        for pixelBuffer: CVPixelBuffer,
        renderColorSpace: CGColorSpace
    ) -> [CIImageOption: Any] {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            return [:]
        default:
            return [.colorSpace: renderColorSpace]
        }
    }

    private func toneMapHDRToSDRSoftwareFallback(_ image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIToneMapHeadroom") else {
            return image
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(
            ShadowClientRealtimeSessionColorPipeline.hdrToSdrToneMapSourceHeadroom,
            forKey: "inputSourceHeadroom"
        )
        filter.setValue(
            ShadowClientRealtimeSessionColorPipeline.hdrToSdrToneMapTargetHeadroom,
            forKey: "inputTargetHeadroom"
        )
        return filter.outputImage ?? image
    }

    private func expandVideoRange(
        _ image: CIImage,
        scale: CGFloat,
        bias: CGFloat
    ) -> CIImage {
        image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ]
        )
    }
}
#endif
