import SwiftUI

#if os(iOS) || os(tvOS)
import CoreImage
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
    private var cachedSupportsExtendedDynamicRange = false
    private var lastExtendedDynamicRangeProbeUptime: TimeInterval = 0
    private var lastRenderedFrameRevision: UInt64 = .max
    private var lastRenderedDrawableSize: CGSize = .zero
    private var hasDumpedCurrentSessionFrameDiagnostics = false
    private var hasDumpedCurrentSessionDrawableSample = false

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
        self.yuvPipeline = nil
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
            hasDumpedCurrentSessionFrameDiagnostics = false
            hasDumpedCurrentSessionDrawableSample = false
        }
        let colorConfiguration = pixelBuffer.map {
            ShadowClientRealtimeSessionColorPipeline.configuration(
                for: $0,
                allowExtendedDynamicRange: surfaceContext.activeDynamicRangeMode == .hdr
            )
        }

        if let colorConfiguration, let pixelBuffer {
            let supportsExtendedDynamicRange = cachedExtendedDynamicRangeSupport(for: view)
            applyColorConfiguration(
                colorConfiguration,
                to: view,
                supportsExtendedDynamicRange: supportsExtendedDynamicRange
            )
            _ = pixelBuffer
        }

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        if let pixelBuffer,
           let colorConfiguration,
           let renderPass = view.currentRenderPassDescriptor,
           let yuvPipeline,
           yuvPipeline.canRender(pixelBuffer),
           !colorConfiguration.prefersExtendedDynamicRange
        {
            _ = yuvPipeline.render(
                pixelBuffer: pixelBuffer,
                into: renderPass,
                commandBuffer: commandBuffer,
                drawableSize: drawableSize
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
            surfaceContext.recordPresentedVideoFrame()
            lastRenderedFrameRevision = snapshot.revision
            lastRenderedDrawableSize = drawableSize
            return
        }

        if let pixelBuffer, let colorConfiguration {
            let supportsExtendedDynamicRange = cachedExtendedDynamicRangeSupport(for: view)
            let shouldToneMapHDRToSDR =
                colorConfiguration.prefersExtendedDynamicRange && !supportsExtendedDynamicRange

            let sourceOptions: [CIImageOption: Any] = [
                .colorSpace: colorConfiguration.renderColorSpace,
            ]
            var sourceImage = CIImage(
                cvPixelBuffer: pixelBuffer,
                options: sourceOptions
            )
            if let expansion = colorConfiguration.videoRangeExpansion {
                sourceImage = expandVideoRange(
                    sourceImage,
                    scale: expansion.scale,
                    bias: expansion.bias
                )
            }
            if shouldToneMapHDRToSDR {
                sourceImage = toneMapHDRToSDRSoftwareFallback(sourceImage)
            }
            let outputColorSpace = shouldToneMapHDRToSDR
                ? ShadowClientRealtimeSessionColorPipeline.defaultDisplayColorSpace
                : colorConfiguration.displayColorSpace
            dumpFrameDiagnosticsIfNeeded(
                view: view,
                pixelBuffer: pixelBuffer,
                configuration: colorConfiguration,
                snapshotRevision: snapshot.revision,
                sourceImage: sourceImage,
                outputColorSpace: outputColorSpace,
                supportsExtendedDynamicRange: supportsExtendedDynamicRange,
                shouldToneMapHDRToSDR: shouldToneMapHDRToSDR
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
        supportsExtendedDynamicRange: Bool
    ) {
        let shouldRenderExtendedDynamicRange =
            configuration.prefersExtendedDynamicRange && supportsExtendedDynamicRange

        let targetPixelFormat: MTLPixelFormat = shouldRenderExtendedDynamicRange
            ? configuration.pixelFormat
            : .bgra8Unorm
        if view.colorPixelFormat != targetPixelFormat {
            view.colorPixelFormat = targetPixelFormat
        }

        if #available(iOS 16.0, tvOS 16.0, *),
           let metalLayer = view.layer as? CAMetalLayer
        {
            metalLayer.colorspace = shouldRenderExtendedDynamicRange
                ? configuration.displayColorSpace
                : ShadowClientRealtimeSessionColorPipeline.defaultDisplayColorSpace
            metalLayer.wantsExtendedDynamicRangeContent = shouldRenderExtendedDynamicRange
        }
    }

    private func supportsExtendedDynamicRangeDisplay(for view: MTKView) -> Bool {
        guard #available(iOS 16.0, tvOS 16.0, *) else {
            return false
        }
        let screen = view.window?.screen ?? UIScreen.main
        return screen.potentialEDRHeadroom > 1.0
    }

    private func cachedExtendedDynamicRangeSupport(for view: MTKView) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastExtendedDynamicRangeProbeUptime > 1.0 {
            cachedSupportsExtendedDynamicRange = supportsExtendedDynamicRangeDisplay(for: view)
            lastExtendedDynamicRangeProbeUptime = now
        }
        return cachedSupportsExtendedDynamicRange
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

    private func dumpFrameDiagnosticsIfNeeded(
        view: MTKView,
        pixelBuffer: CVPixelBuffer,
        configuration: ShadowClientRealtimeSessionColorConfiguration,
        snapshotRevision: UInt64,
        sourceImage: CIImage,
        outputColorSpace: CGColorSpace,
        supportsExtendedDynamicRange: Bool,
        shouldToneMapHDRToSDR: Bool
    ) {
        guard !hasDumpedCurrentSessionFrameDiagnostics else {
            return
        }

        hasDumpedCurrentSessionFrameDiagnostics = true

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let primaries = attachmentValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let transfer = attachmentValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let matrix = attachmentValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let bufferColorSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue().name as String? ?? "nil"
        let renderColorSpace = configuration.renderColorSpace.name as String? ?? "nil"
        let displayColorSpace = configuration.displayColorSpace.name as String? ?? "nil"
        let outputColorSpaceName = outputColorSpace.name as String? ?? "nil"
        let planeSummary = summarizePlanes(pixelBuffer)
        let ciAverageRGBA = sampledAverageRGBA(
            for: sourceImage,
            colorSpace: outputColorSpace
        ) ?? "nil"
        let ciCenterRGBA = sampledCenterRGBA(
            for: sourceImage,
            colorSpace: outputColorSpace
        ) ?? "nil"
        let ciCenter709 = sampledCenterRGBA(
            for: sourceImage,
            colorSpace: CGColorSpace(name: CGColorSpace.itur_709) ?? configuration.renderColorSpace
        ) ?? "nil"
        let ciCenterSRGB = sampledCenterRGBA(
            for: sourceImage,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? configuration.displayColorSpace
        ) ?? "nil"
        let centerYUVSummary = sampledCenterYUVSummary(pixelBuffer) ?? "nil"

        logger.notice(
            """
            Frame dump revision=\(snapshotRevision, privacy: .public) pixel-format=0x\(String(pixelFormat, radix: 16), privacy: .public) size=\(width, privacy: .public)x\(height, privacy: .public) primaries=\(primaries, privacy: .public) transfer=\(transfer, privacy: .public) matrix=\(matrix, privacy: .public) buffer-colorspace=\(bufferColorSpace, privacy: .public) render-colorspace=\(renderColorSpace, privacy: .public) display-colorspace=\(displayColorSpace, privacy: .public) output-colorspace=\(outputColorSpaceName, privacy: .public) pixel-format-target=\(view.colorPixelFormat.rawValue, privacy: .public) supports-edr=\(supportsExtendedDynamicRange, privacy: .public) tone-map=\(shouldToneMapHDRToSDR, privacy: .public) edr=\(configuration.prefersExtendedDynamicRange, privacy: .public) planes=\(planeSummary, privacy: .public) center-yuv=\(centerYUVSummary, privacy: .public) ci-average=\(ciAverageRGBA, privacy: .public) ci-center=\(ciCenterRGBA, privacy: .public) ci-center-709=\(ciCenter709, privacy: .public) ci-center-srgb=\(ciCenterSRGB, privacy: .public)
            """
        )
    }

    private func sampledAverageRGBA(
        for image: CIImage,
        colorSpace: CGColorSpace
    ) -> String? {
        guard let filter = CIFilter(name: "CIAreaAverage") else {
            return nil
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: image.extent), forKey: kCIInputExtentKey)
        guard let outputImage = filter.outputImage else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            outputImage,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: colorSpace
        )
        return "[\(bytes[0]),\(bytes[1]),\(bytes[2]),\(bytes[3])]"
    }

    private func sampledCenterRGBA(
        for image: CIImage,
        colorSpace: CGColorSpace
    ) -> String? {
        let extent = image.extent.integral
        guard extent.width >= 1, extent.height >= 1,
              let cgImage = ciContext.createCGImage(image, from: extent, format: .RGBA8, colorSpace: colorSpace)
        else {
            return nil
        }

        guard let providerData = cgImage.dataProvider?.data,
              let dataPointer = CFDataGetBytePtr(providerData)
        else {
            return nil
        }

        let centerX = max(0, min(cgImage.width - 1, cgImage.width / 2))
        let centerY = max(0, min(cgImage.height - 1, cgImage.height / 2))
        let bytesPerPixel = 4
        let offset = centerY * cgImage.bytesPerRow + centerX * bytesPerPixel
        return "[\(dataPointer[offset]),\(dataPointer[offset + 1]),\(dataPointer[offset + 2]),\(dataPointer[offset + 3])]"
    }

    private func sampledCenterYUVSummary(_ pixelBuffer: CVPixelBuffer) -> String? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
            pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let centerX = max(0, min(width - 1, width / 2))
        let centerY = max(0, min(height - 1, height / 2))
        let yRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)

        let yPointer = yBase.bindMemory(to: UInt8.self, capacity: yRowBytes * height)
        let uvPointer = uvBase.bindMemory(
            to: UInt8.self,
            capacity: uvRowBytes * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        )

        let ySample = Int(yPointer[centerY * yRowBytes + centerX])
        let uvX = (centerX / 2) * 2
        let uvY = centerY / 2
        let uvOffset = uvY * uvRowBytes + uvX
        let cbSample = Int(uvPointer[uvOffset])
        let crSample = Int(uvPointer[uvOffset + 1])

        let fullRangeRGB = convertBT709(y: ySample, cb: cbSample, cr: crSample, fullRange: true)
        let videoRangeRGB = convertBT709(y: ySample, cb: cbSample, cr: crSample, fullRange: false)

        return "Y=\(ySample),Cb=\(cbSample),Cr=\(crSample),full=\(fullRangeRGB),video=\(videoRangeRGB)"
    }

    private func convertBT709(y: Int, cb: Int, cr: Int, fullRange: Bool) -> String {
        let yf = Double(y)
        let cbf = Double(cb) - 128.0
        let crf = Double(cr) - 128.0

        let scaledY: Double
        let scaledCb: Double
        let scaledCr: Double

        if fullRange {
            scaledY = yf
            scaledCb = cbf
            scaledCr = crf
        } else {
            scaledY = max(0.0, (yf - 16.0) * (255.0 / 219.0))
            scaledCb = cbf * (255.0 / 224.0)
            scaledCr = crf * (255.0 / 224.0)
        }

        let r = clampToByte(scaledY + 1.5748 * scaledCr)
        let g = clampToByte(scaledY - 0.1873 * scaledCb - 0.4681 * scaledCr)
        let b = clampToByte(scaledY + 1.8556 * scaledCb)
        return "[\(r),\(g),\(b)]"
    }

    private func clampToByte(_ value: Double) -> Int {
        Int(max(0.0, min(255.0, value.rounded())))
    }

    private func summarizePlanes(_ pixelBuffer: CVPixelBuffer) -> String {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let planeCount = max(CVPixelBufferGetPlaneCount(pixelBuffer), 1)
        var parts: [String] = []

        for planeIndex in 0..<planeCount {
            let baseAddress: UnsafeMutableRawPointer?
            let width: Int
            let height: Int
            let bytesPerRow: Int

            if CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
                baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex)
                width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
                height = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
                bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
            } else {
                baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)
                width = CVPixelBufferGetWidth(pixelBuffer)
                height = CVPixelBufferGetHeight(pixelBuffer)
                bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            }

            guard let baseAddress else {
                parts.append("plane\(planeIndex)=nil")
                continue
            }

            let bytesPerSample = bytesPerRow / max(width, 1)
            if bytesPerSample >= 2 {
                let pointer = baseAddress.bindMemory(to: UInt16.self, capacity: (bytesPerRow * height) / 2)
                var minValue = UInt16.max
                var maxValue = UInt16.min
                for row in 0..<height {
                    let rowPointer = pointer.advanced(by: (bytesPerRow / 2) * row)
                    for column in 0..<width {
                        let value = rowPointer[column]
                        minValue = min(minValue, value)
                        maxValue = max(maxValue, value)
                    }
                }
                parts.append("plane\(planeIndex)=\(minValue)-\(maxValue)")
            } else {
                let pointer = baseAddress.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
                var minValue = UInt8.max
                var maxValue = UInt8.min
                for row in 0..<height {
                    let rowPointer = pointer.advanced(by: bytesPerRow * row)
                    for column in 0..<width {
                        let value = rowPointer[column]
                        minValue = min(minValue, value)
                        maxValue = max(maxValue, value)
                    }
                }
                parts.append("plane\(planeIndex)=\(minValue)-\(maxValue)")
            }
        }

        return parts.joined(separator: ",")
    }

    private func attachmentValue(forKey key: CFString, pixelBuffer: CVPixelBuffer) -> String? {
        guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
            return nil
        }
        return attachment as? String
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
            logger.notice("Drawable sample skipped unsupported pixel-format=\(texture.pixelFormat.rawValue, privacy: .public)")
            return
        }
        guard let stagingTexture = makeDrawableSampleTexture(pixelFormat: texture.pixelFormat) else {
            logger.error("Drawable sample staging texture allocation failed")
            return
        }

        hasDumpedCurrentSessionDrawableSample = true
        let centerX = max(0, min(texture.width - 1, texture.width / 2))
        let centerY = max(0, min(texture.height - 1, texture.height / 2))
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            logger.error("Drawable sample blit encoder allocation failed")
            return
        }

        blitEncoder.copy(
            from: texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: centerX, y: centerY, z: 0),
            sourceSize: MTLSize(width: 1, height: 1, depth: 1),
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

            self.logger.notice("Drawable center RGBA=\(sampledRGBA, privacy: .public)")
        }
    }

    private func makeDrawableSampleTexture(pixelFormat: MTLPixelFormat) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: 1,
            height: 1,
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

        var bytes = [UInt8](repeating: 0, count: 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        let blue = bytes[0]
        let green = bytes[1]
        let red = bytes[2]
        let alpha = bytes[3]
        return "[\(red),\(green),\(blue),\(alpha)]"
    }
}
#endif
