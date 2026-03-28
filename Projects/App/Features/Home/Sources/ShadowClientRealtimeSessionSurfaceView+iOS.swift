import SwiftUI

#if os(iOS) || os(tvOS)
import CoreVideo
import Foundation
@preconcurrency import Metal
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
    private final class SampledTextureBox: @unchecked Sendable {
        let texture: any MTLTexture

        init(texture: any MTLTexture) {
            self.texture = texture
        }
    }

    private struct DrawableSampleRegion {
        let minX: Int
        let minY: Int
        let width: Int
        let height: Int

        var summary: String {
            "[x=\(minX),y=\(minY),w=\(width),h=\(height)]"
        }
    }

    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "SurfaceView.iOS")
    private let surfaceContext: ShadowClientRealtimeSessionSurfaceContext
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let yuvPipeline: ShadowClientRealtimeSessionYUVMetalPipeline?
    private var frameStreamTask: Task<Void, Never>?
    private var latestSnapshot = ShadowClientRealtimeSessionFrameStore.Snapshot(
        pixelBuffer: nil,
        hdrFrameState: nil,
        revision: 0
    )
    private var lastRenderedFrameRevision: UInt64 = .max
    private var lastRenderedDrawableSize: CGSize = .zero
    private var hasDumpedCurrentSessionDrawableSample = false
    private var hasLoggedRenderPathForCurrentSession = false
    private var lastLoggedEDRMetadataSummary: String?

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
            lastLoggedEDRMetadataSummary = nil
        }
        let colorConfiguration = pixelBuffer.map {
            ShadowClientRealtimeSessionColorPipeline.configuration(
                for: $0,
                allowExtendedDynamicRange: surfaceContext.activeDynamicRangeMode == .hdr,
                negotiatedHDRMetadata: surfaceContext.activeHDRMetadata
            )
        }
        let renderTargetConfiguration = colorConfiguration.map { colorConfiguration in
            ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
                colorConfiguration: colorConfiguration,
                supportsExtendedDynamicRange: supportsExtendedDynamicRangeDisplay(for: view),
                renderBackend: .metalYUV,
                screenColorSpace: screenColorSpace(for: view)
            )
        }

        if let colorConfiguration, let renderTargetConfiguration, pixelBuffer != nil {
            applyColorConfiguration(
                colorConfiguration,
                renderTargetConfiguration,
                pixelBuffer: pixelBuffer,
                to: view,
                supportsExtendedDynamicRange: supportsExtendedDynamicRangeDisplay(for: view)
            )
        }

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        if let pixelBuffer,
           let renderTargetConfiguration,
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
                colorPixelFormat: view.colorPixelFormat,
                outputColorSpace: renderTargetConfiguration.outputColorSpace,
                prefersExtendedDynamicRange: renderTargetConfiguration.prefersExtendedDynamicRange,
                currentEDRHeadroom: currentExtendedDynamicRangeHeadroom(for: view)
            )
            if didRender {
                commandBuffer.present(drawable)
                scheduleDrawableTextureSampleIfNeeded(
                    drawable: drawable,
                    commandBuffer: commandBuffer,
                    videoSize: CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    ),
                    drawableSize: drawableSize
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
                commandBuffer: commandBuffer,
                videoSize: pixelBuffer.map {
                    CGSize(
                        width: CVPixelBufferGetWidth($0),
                        height: CVPixelBufferGetHeight($0)
                    )
                },
                drawableSize: drawableSize
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
        _ colorConfiguration: ShadowClientRealtimeSessionColorConfiguration,
        _ renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration,
        pixelBuffer: CVPixelBuffer?,
        to view: MTKView,
        supportsExtendedDynamicRange _: Bool
    ) {
        if view.colorPixelFormat != renderTargetConfiguration.targetPixelFormat {
            view.colorPixelFormat = renderTargetConfiguration.targetPixelFormat
        }

        if let metalLayer = view.layer as? CAMetalLayer {
            metalLayer.colorspace = renderTargetConfiguration.outputColorSpace
            metalLayer.wantsExtendedDynamicRangeContent = renderTargetConfiguration.prefersExtendedDynamicRange
            let currentHeadroom = CGFloat(
                currentExtendedDynamicRangeHeadroom(for: view)
            )
            let appliedHDRMetadata = ShadowClientSurfaceColorSpaceKit.renderedFrameHDRMetadata(
                colorConfiguration: colorConfiguration,
                pixelBuffer: pixelBuffer
            )
            let edrMetadataSummary = ShadowClientSurfaceColorSpaceKit.edrMetadataDebugSummary(
                colorConfiguration: colorConfiguration,
                renderTargetConfiguration: renderTargetConfiguration,
                hdrMetadata: appliedHDRMetadata,
                currentHeadroom: currentHeadroom
            )
            if edrMetadataSummary != lastLoggedEDRMetadataSummary {
                logger.notice("Surface EDR metadata applied \(edrMetadataSummary, privacy: .public)")
                lastLoggedEDRMetadataSummary = edrMetadataSummary
            }
            metalLayer.edrMetadata = ShadowClientSurfaceColorSpaceKit.edrMetadata(
                colorConfiguration: colorConfiguration,
                renderTargetConfiguration: renderTargetConfiguration,
                hdrMetadata: appliedHDRMetadata,
                currentHeadroom: currentHeadroom
            )
        }
    }

    private func supportsExtendedDynamicRangeDisplay(for view: MTKView) -> Bool {
        let screen = view.window?.screen ?? UIScreen.main
        return screen.potentialEDRHeadroom > 1.0
    }

    private func currentExtendedDynamicRangeHeadroom(for view: MTKView) -> Float {
        let screen = view.window?.screen ?? UIScreen.main
        return Float(max(screen.currentEDRHeadroom, 1.0))
    }

    private func screenColorSpace(for view: MTKView) -> CGColorSpace? {
        let screen = view.window?.screen ?? UIScreen.main
        switch screen.traitCollection.displayGamut {
        case .P3:
            return CGColorSpace(name: CGColorSpace.displayP3)
        default:
            return nil
        }
    }

    private func scheduleDrawableTextureSampleIfNeeded(
        drawable: CAMetalDrawable,
        commandBuffer: MTLCommandBuffer,
        videoSize: CGSize?,
        drawableSize: CGSize
    ) {
        guard !hasDumpedCurrentSessionDrawableSample else {
            return
        }

        let texture = drawable.texture
        guard
            texture.pixelFormat == .bgra8Unorm ||
            texture.pixelFormat == .bgra8Unorm_srgb ||
            texture.pixelFormat == .rgba16Float
        else {
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
        let sampledTextureBox = SampledTextureBox(texture: stagingTexture)
        let contentRegion = Self.drawableSampleRegion(
            videoSize: videoSize,
            drawableSize: drawableSize,
            textureWidth: texture.width,
            textureHeight: texture.height
        )
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

        commandBuffer.addCompletedHandler { [weak self, sampledTextureBox] _ in
            guard let self else {
                return
            }

            let fullSampledRGBA = Self.sampleDrawableTextureRGBA(sampledTextureBox.texture)
            guard let fullSampledRGBA else {
                self.logger.error("Drawable texture sample failed")
                return
            }

            guard let contentRegion else {
                self.logger.notice("Drawable samples full=\(fullSampledRGBA, privacy: .public)")
                return
            }

            let contentSampledRGBA = Self.sampleDrawableTextureRGBA(
                sampledTextureBox.texture,
                region: contentRegion
            ) ?? "unavailable"
            self.logger.notice(
                "Drawable samples full=\(fullSampledRGBA, privacy: .public) content-region=\(contentRegion.summary, privacy: .public) content=\(contentSampledRGBA, privacy: .public)"
            )
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

    nonisolated private static func drawableSampleRegion(
        videoSize: CGSize?,
        drawableSize: CGSize,
        textureWidth: Int,
        textureHeight: Int
    ) -> DrawableSampleRegion? {
        guard let videoSize,
              videoSize.width > 0,
              videoSize.height > 0,
              drawableSize.width > 0,
              drawableSize.height > 0,
              textureWidth > 0,
              textureHeight > 0
        else {
            return nil
        }

        let widthScale = drawableSize.width / videoSize.width
        let heightScale = drawableSize.height / videoSize.height
        let scale = min(widthScale, heightScale)
        let scaledWidth = videoSize.width * scale
        let scaledHeight = videoSize.height * scale
        let originX = (drawableSize.width - scaledWidth) * 0.5
        let originY = (drawableSize.height - scaledHeight) * 0.5

        let normalizedMinX = originX / drawableSize.width
        let normalizedMaxX = (originX + scaledWidth) / drawableSize.width
        let normalizedMinY = originY / drawableSize.height
        let normalizedMaxY = (originY + scaledHeight) / drawableSize.height

        let minX = max(0, min(textureWidth - 1, Int(round(normalizedMinX * CGFloat(textureWidth - 1)))))
        let maxX = max(0, min(textureWidth - 1, Int(round(normalizedMaxX * CGFloat(textureWidth - 1)))))
        let minY = max(0, min(textureHeight - 1, Int(round(normalizedMinY * CGFloat(textureHeight - 1)))))
        let maxY = max(0, min(textureHeight - 1, Int(round(normalizedMaxY * CGFloat(textureHeight - 1)))))
        let width = max(1, maxX - minX + 1)
        let height = max(1, maxY - minY + 1)

        return DrawableSampleRegion(
            minX: minX,
            minY: minY,
            width: width,
            height: height
        )
    }

    nonisolated private static func sampleDrawableTextureRGBA(
        _ texture: any MTLTexture,
        region: DrawableSampleRegion? = nil
    ) -> String? {
        let minX = region?.minX ?? 0
        let minY = region?.minY ?? 0
        let width = region?.width ?? texture.width
        let height = region?.height ?? texture.height
        let maxX = min(texture.width - 1, minX + max(0, width - 1))
        let maxY = min(texture.height - 1, minY + max(0, height - 1))
        let labels: [(String, Int, Int)] = [
            ("tl", sampleCoordinate(lowerBound: minX, upperBound: maxX, fraction: 0.1), sampleCoordinate(lowerBound: minY, upperBound: maxY, fraction: 0.1)),
            ("tr", sampleCoordinate(lowerBound: minX, upperBound: maxX, fraction: 0.9), sampleCoordinate(lowerBound: minY, upperBound: maxY, fraction: 0.1)),
            ("c", sampleCoordinate(lowerBound: minX, upperBound: maxX, fraction: 0.5), sampleCoordinate(lowerBound: minY, upperBound: maxY, fraction: 0.5)),
            ("bl", sampleCoordinate(lowerBound: minX, upperBound: maxX, fraction: 0.1), sampleCoordinate(lowerBound: minY, upperBound: maxY, fraction: 0.9)),
            ("br", sampleCoordinate(lowerBound: minX, upperBound: maxX, fraction: 0.9), sampleCoordinate(lowerBound: minY, upperBound: maxY, fraction: 0.9)),
        ]

        switch texture.pixelFormat {
        case .bgra8Unorm, .bgra8Unorm_srgb:
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
        case .rgba16Float:
            var parts: [String] = []
            var words = [UInt16](repeating: 0, count: 4)
            for (label, x, y) in labels {
                texture.getBytes(
                    &words,
                    bytesPerRow: MemoryLayout<UInt16>.stride * words.count,
                    from: MTLRegionMake2D(x, y, 1, 1),
                    mipmapLevel: 0
                )
                let red = Float(Float16(bitPattern: words[0]))
                let green = Float(Float16(bitPattern: words[1]))
                let blue = Float(Float16(bitPattern: words[2]))
                let alpha = Float(Float16(bitPattern: words[3]))
                parts.append(
                    "\(label)=[\(String(format: "%.6f", red)),\(String(format: "%.6f", green)),\(String(format: "%.6f", blue)),\(String(format: "%.6f", alpha))]"
                )
            }
            return parts.joined(separator: " ")
        default:
            return nil
        }
    }

    nonisolated private static func sampleCoordinate(lowerBound: Int, upperBound: Int, fraction: CGFloat) -> Int {
        let clampedFraction = Swift.min(Swift.max(fraction, 0), 1)
        let span = CGFloat(upperBound - lowerBound)
        return lowerBound + Int(round(span * clampedFraction))
    }

}
#endif
