import SwiftUI

#if os(iOS) || os(tvOS)
import CoreVideo
import Foundation
@preconcurrency import MetalKit
import os
import UIKit

struct ShadowClientRealtimeSessionSurfaceRepresentable: UIViewRepresentable {
    let surfaceContext: ShadowClientRealtimeSessionSurfaceContext

    final class Coordinator {
        var renderer: ShadowClientRealtimeSessionMetalRenderer?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        guard let device = MTLCreateSystemDefaultDevice(),
              let renderer = ShadowClientRealtimeSessionMetalRenderer(
                device: device,
                surfaceContext: surfaceContext
              )
        else {
            let fallback = UIView()
            fallback.isOpaque = true
            fallback.backgroundColor = .black
            return fallback
        }

        let view = MTKView(frame: .zero, device: device)
        view.isOpaque = true
        view.backgroundColor = .black
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = surfaceContext.preferredRenderFPS
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let view = uiView as? MTKView {
            view.isPaused = false
            if view.preferredFramesPerSecond != surfaceContext.preferredRenderFPS {
                view.preferredFramesPerSecond = surfaceContext.preferredRenderFPS
            }
        } else {
            uiView.backgroundColor = .black
        }
    }
}

@MainActor
final class ShadowClientRealtimeSessionMetalRenderer: NSObject, MTKViewDelegate {
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "SurfaceView.iOS")
    private let surfaceContext: ShadowClientRealtimeSessionSurfaceContext
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let yuvPipeline: ShadowClientRealtimeSessionYUVMetalPipeline?
    private var frameStreamTask: Task<Void, Never>?
    private var latestSnapshot = ShadowClientRealtimeSessionFrameStore.Snapshot(
        pixelBuffer: nil,
        revision: 0
    )
    private var lastRenderedFrameRevision: UInt64 = .max
    private var lastRenderedDrawableSize: CGSize = .zero
    private var hasDumpedCurrentSessionDrawableSample = false
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
            hasDumpedCurrentSessionDrawableSample = false
            hasLoggedRenderPathForCurrentSession = false
        }
        let colorConfiguration = pixelBuffer.map {
            ShadowClientRealtimeSessionColorPipeline.configuration(
                for: $0,
                allowExtendedDynamicRange: surfaceContext.activeDynamicRangeMode == .hdr
            )
        }

        if let colorConfiguration, let pixelBuffer {
            let supportsExtendedDynamicRange = supportsExtendedDynamicRangeDisplay(for: view)
            let renderTargetConfiguration = ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
                colorConfiguration: colorConfiguration,
                supportsExtendedDynamicRange: supportsExtendedDynamicRange,
                renderBackend: .metalYUV
            )
            applyColorConfiguration(
                renderTargetConfiguration,
                to: view,
                supportsExtendedDynamicRange: supportsExtendedDynamicRange
            )
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
                scheduleDrawableTextureSampleIfNeeded(
                    drawable: drawable,
                    commandBuffer: commandBuffer
                )
                commandBuffer.commit()
                surfaceContext.recordPresentedVideoFrame()
                lastRenderedFrameRevision = snapshot.revision
                lastRenderedDrawableSize = drawableSize
                return
            }
            logger.error("Surface render path=metal-yuv failed; preserving clear frame without Core Image fallback")
        } else if let unsupportedPixelBuffer = pixelBuffer {
            logger.error("Surface render path=metal-yuv unavailable for pixel-format=0x\(String(CVPixelBufferGetPixelFormatType(unsupportedPixelBuffer), radix: 16), privacy: .public); preserving clear frame without Core Image fallback")
        }

        if let renderPass = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        {
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        if pixelBuffer != nil {
            scheduleDrawableTextureSampleIfNeeded(
                drawable: drawable,
                commandBuffer: commandBuffer
            )
        }
        commandBuffer.commit()
        if pixelBuffer != nil {
            surfaceContext.recordPresentedVideoFrame()
        }
        lastRenderedFrameRevision = snapshot.revision
        lastRenderedDrawableSize = drawableSize
    }

    private func applyColorConfiguration(
        _ renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration,
        to view: MTKView,
        supportsExtendedDynamicRange _: Bool
    ) {
        if view.colorPixelFormat != renderTargetConfiguration.targetPixelFormat {
            view.colorPixelFormat = renderTargetConfiguration.targetPixelFormat
        }

        if #available(iOS 16.0, tvOS 16.0, *),
           let metalLayer = view.layer as? CAMetalLayer
        {
            metalLayer.colorspace = renderTargetConfiguration.outputColorSpace
            metalLayer.wantsExtendedDynamicRangeContent = renderTargetConfiguration.prefersExtendedDynamicRange
        }
    }

    private func supportsExtendedDynamicRangeDisplay(for view: MTKView) -> Bool {
        guard #available(iOS 16.0, tvOS 16.0, *) else {
            return false
        }
        let screen = view.window?.screen ?? UIScreen.main
        return screen.potentialEDRHeadroom > 1.0
    }

    private func scheduleDrawableTextureSampleIfNeeded(
        drawable: CAMetalDrawable,
        commandBuffer: MTLCommandBuffer
    ) {
        guard !hasDumpedCurrentSessionDrawableSample else {
            return
        }

        let texture = drawable.texture
        guard texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb else {
            hasDumpedCurrentSessionDrawableSample = true
            logger.notice("Drawable sample skipped unsupported pixel-format=\(texture.pixelFormat.rawValue, privacy: .public)")
            return
        }
        guard let stagingTexture = makeDrawableSampleTexture(
            pixelFormat: texture.pixelFormat,
            width: texture.width,
            height: texture.height
        ) else {
            logger.error("Drawable sample staging texture allocation failed")
            return
        }

        hasDumpedCurrentSessionDrawableSample = true
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            logger.error("Drawable sample blit encoder allocation failed")
            return
        }

        blitEncoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
            to: stagingTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        blitEncoder.endEncoding()

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else {
                return
            }

            let sampledRGBA = Self.sampleDrawableTextureRGBA(stagingTexture)
            guard let sampledRGBA else {
                self.logger.error("Drawable texture sample failed")
                return
            }

            self.logger.notice("Drawable samples RGBA=\(sampledRGBA, privacy: .public)")
        }
    }

    private func makeDrawableSampleTexture(
        pixelFormat: MTLPixelFormat,
        width: Int,
        height: Int
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: max(1, width),
            height: max(1, height),
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.shaderRead, .shaderWrite]
        return commandQueue.device.makeTexture(descriptor: descriptor)
    }

    nonisolated private static func sampleDrawableTextureRGBA(_ texture: any MTLTexture) -> String? {
        guard texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb else {
            return nil
        }

        let labels: [(String, Int, Int)] = [
            ("tl", max(0, texture.width / 10), max(0, texture.height / 10)),
            ("tr", max(0, texture.width - 1 - texture.width / 10), max(0, texture.height / 10)),
            ("c", max(0, texture.width / 2), max(0, texture.height / 2)),
            ("bl", max(0, texture.width / 10), max(0, texture.height - 1 - texture.height / 10)),
            ("br", max(0, texture.width - 1 - texture.width / 10), max(0, texture.height - 1 - texture.height / 10)),
        ]
        var parts: [String] = []
        var bytes = [UInt8](repeating: 0, count: 4)
        for (label, x, y) in labels {
            texture.getBytes(
                &bytes,
                bytesPerRow: 4,
                from: MTLRegionMake2D(x, y, 1, 1),
                mipmapLevel: 0
            )
            let blue = bytes[0]
            let green = bytes[1]
            let red = bytes[2]
            let alpha = bytes[3]
            parts.append("\(label)=\(red),\(green),\(blue),\(alpha)")
        }
        return parts.joined(separator: " ")
    }

}
#endif
