import SwiftUI

#if os(iOS) || os(tvOS)
import CoreImage
import CoreVideo
import Foundation
import MetalKit
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
        view.colorPixelFormat = .bgra8Unorm_srgb
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
    private let surfaceContext: ShadowClientRealtimeSessionSurfaceContext
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
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

        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        if let pixelBuffer = snapshot.pixelBuffer?.value {
            let colorConfiguration = ShadowClientRealtimeSessionColorPipeline.configuration(
                for: pixelBuffer,
                allowExtendedDynamicRange: surfaceContext.activeDynamicRangeMode == .hdr
            )
            let supportsExtendedDynamicRange = cachedExtendedDynamicRangeSupport(for: view)
            let shouldToneMapHDRToSDR =
                colorConfiguration.prefersExtendedDynamicRange && !supportsExtendedDynamicRange

            applyColorConfiguration(
                colorConfiguration,
                to: view,
                supportsExtendedDynamicRange: supportsExtendedDynamicRange
            )

            var sourceOptions: [CIImageOption: Any] = [:]
            if ShadowClientRealtimeSessionColorPipeline.shouldAttachExplicitSourceColorSpace(for: pixelBuffer) {
                sourceOptions[.colorSpace] = colorConfiguration.renderColorSpace
            }
            var sourceImage = CIImage(
                cvPixelBuffer: pixelBuffer,
                options: sourceOptions
            )
            if shouldToneMapHDRToSDR {
                sourceImage = toneMapHDRToSDRSoftwareFallback(sourceImage)
            }
            let outputColorSpace = shouldToneMapHDRToSDR
                ? ShadowClientRealtimeSessionColorPipeline.defaultDisplayColorSpace
                : colorConfiguration.displayColorSpace
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
            : .bgra8Unorm_srgb
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
        return screen.currentEDRHeadroom > 1.01
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
}
#endif
