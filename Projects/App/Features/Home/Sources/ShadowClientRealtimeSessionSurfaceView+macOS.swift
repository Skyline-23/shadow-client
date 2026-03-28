import SwiftUI

#if os(macOS)
import AppKit
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
    private struct RenderTargetSignature: Equatable {
        let pixelFormat: MTLPixelFormat
        let prefersExtendedDynamicRange: Bool
        let outputColorSpaceName: String?
    }

    private let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "SurfaceView.macOS"
    )
    private let surfaceContext: ShadowClientRealtimeSessionSurfaceContext
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let yuvPipeline: ShadowClientRealtimeSessionYUVMetalPipeline?
    private var frameStreamTask: Task<Void, Never>?
    private var latestSnapshot = ShadowClientRealtimeSessionFrameStore.Snapshot(
        pixelBuffer: nil,
        hdrFrameState: nil,
        frameLatencyTrace: nil,
        revision: 0
    )
    private var lastRenderedFrameRevision: UInt64 = .max
    private var lastRenderedColorConfigurationRevision: UInt64 = .max
    private var lastRenderedDrawableSize: CGSize = .zero
    private var hasLoggedRenderPathForCurrentSession = false
    private var lastAppliedRenderTargetSignature: RenderTargetSignature?

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
        let colorConfigurationRevision = surfaceContext.colorConfigurationRevision
        if snapshot.revision == lastRenderedFrameRevision,
           colorConfigurationRevision == lastRenderedColorConfigurationRevision,
           drawableSize == lastRenderedDrawableSize
        {
            return
        }

        let pixelBuffer = snapshot.pixelBuffer?.value
        if pixelBuffer == nil {
            hasLoggedRenderPathForCurrentSession = false
            lastAppliedRenderTargetSignature = nil
        }
        let allowsExtendedDynamicRange =
            ShadowClientRealtimeSessionHDRCompositor.allowsExtendedDynamicRange(
                dynamicRangeMode: surfaceContext.activeDynamicRangeMode,
                hdrFrameState: snapshot.hdrFrameState
            )
        let colorConfiguration = pixelBuffer.map {
            ShadowClientRealtimeSessionColorPipeline.configuration(
                for: $0,
                allowExtendedDynamicRange: allowsExtendedDynamicRange,
                negotiatedHDRMetadata: surfaceContext.activeHDRMetadata
            )
        }
        let renderTargetConfiguration = colorConfiguration.map { colorConfiguration in
            ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
                colorConfiguration: colorConfiguration,
                supportsExtendedDynamicRange: supportsExtendedDynamicRangeDisplay(for: view),
                renderBackend: .metalYUV,
                screenColorSpace: (view.window?.screen ?? NSScreen.main)?.colorSpace?.cgColorSpace
            )
        }

        if let colorConfiguration, let renderTargetConfiguration, pixelBuffer != nil {
            let renderTargetSignature = Self.renderTargetSignature(for: renderTargetConfiguration)
            let didResetDrawablePool = applyColorConfiguration(
                colorConfiguration,
                renderTargetConfiguration,
                pixelBuffer: pixelBuffer,
                signature: renderTargetSignature,
                to: view,
                supportsExtendedDynamicRange: supportsExtendedDynamicRangeDisplay(for: view)
            )
            if didResetDrawablePool {
                logger.notice("Surface render target changed; released drawable pool before rendering next frame")
                return
            }
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
            let didRender = ShadowClientRealtimeSessionHDRCompositor.render(
                snapshot: snapshot,
                pixelBuffer: pixelBuffer,
                into: renderPass,
                commandBuffer: commandBuffer,
                drawableSize: drawableSize,
                colorPixelFormat: view.colorPixelFormat,
                renderTargetConfiguration: renderTargetConfiguration,
                yuvPipeline: yuvPipeline,
                currentEDRHeadroom: Float(currentExtendedDynamicRangeHeadroom(for: view)),
                defaultHDRMetadata: surfaceContext.activeHDRMetadata
            )
            if didRender {
                commandBuffer.present(drawable)
                commandBuffer.commit()
                surfaceContext.recordPresentedVideoFrame(frameLatencyTrace: snapshot.frameLatencyTrace)
                lastRenderedFrameRevision = snapshot.revision
                lastRenderedColorConfigurationRevision = colorConfigurationRevision
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
        commandBuffer.commit()
        if pixelBuffer != nil {
            surfaceContext.recordPresentedVideoFrame(frameLatencyTrace: snapshot.frameLatencyTrace)
        }
        lastRenderedFrameRevision = snapshot.revision
        lastRenderedColorConfigurationRevision = colorConfigurationRevision
        lastRenderedDrawableSize = drawableSize
    }

    private func applyColorConfiguration(
        _ colorConfiguration: ShadowClientRealtimeSessionColorConfiguration,
        _ renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration,
        pixelBuffer: CVPixelBuffer?,
        signature: RenderTargetSignature,
        to view: MTKView,
        supportsExtendedDynamicRange _: Bool
    ) -> Bool {
        var requiresDrawableReset = false

        if view.colorPixelFormat != renderTargetConfiguration.targetPixelFormat {
            view.colorPixelFormat = renderTargetConfiguration.targetPixelFormat
            requiresDrawableReset = true
        }
        let outputColorSpaceName = renderTargetConfiguration.outputColorSpace.name as String?
        let currentViewColorSpaceName = view.colorspace?.name as String?
        if currentViewColorSpaceName != outputColorSpaceName {
            requiresDrawableReset = true
        }
        view.colorspace = renderTargetConfiguration.outputColorSpace

        if #available(macOS 10.15, *),
           let metalLayer = view.layer as? CAMetalLayer
        {
            let currentLayerColorSpaceName = metalLayer.colorspace?.name as String?
            if currentLayerColorSpaceName != outputColorSpaceName {
                requiresDrawableReset = true
            }
            if metalLayer.wantsExtendedDynamicRangeContent != renderTargetConfiguration.prefersExtendedDynamicRange {
                requiresDrawableReset = true
            }
            metalLayer.colorspace = renderTargetConfiguration.outputColorSpace
            metalLayer.wantsExtendedDynamicRangeContent = renderTargetConfiguration.prefersExtendedDynamicRange
            let appliedHDRMetadata = ShadowClientSurfaceColorSpaceKit.renderedFrameHDRMetadata(
                colorConfiguration: colorConfiguration,
                pixelBuffer: pixelBuffer
            )
            metalLayer.edrMetadata = ShadowClientSurfaceColorSpaceKit.edrMetadata(
                colorConfiguration: colorConfiguration,
                renderTargetConfiguration: renderTargetConfiguration,
                hdrMetadata: appliedHDRMetadata,
                currentHeadroom: currentExtendedDynamicRangeHeadroom(for: view)
            )
        }

        let didChangeRenderTarget = lastAppliedRenderTargetSignature != signature
        lastAppliedRenderTargetSignature = signature
        if requiresDrawableReset || didChangeRenderTarget {
            view.releaseDrawables()
            return true
        }
        return false
    }

    private static func renderTargetSignature(
        for renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration
    ) -> RenderTargetSignature {
        .init(
            pixelFormat: renderTargetConfiguration.targetPixelFormat,
            prefersExtendedDynamicRange: renderTargetConfiguration.prefersExtendedDynamicRange,
            outputColorSpaceName: renderTargetConfiguration.outputColorSpace.name as String?
        )
    }

    private func supportsExtendedDynamicRangeDisplay(for view: MTKView) -> Bool {
        guard #available(macOS 10.15, *) else {
            return false
        }
        let screen = view.window?.screen ?? NSScreen.main
        let potentialHeadroom = screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1
        return potentialHeadroom > 1.0
    }

    @available(macOS 10.15, *)
    private func currentExtendedDynamicRangeHeadroom(for view: MTKView) -> CGFloat {
        let screen = view.window?.screen ?? NSScreen.main
        return max(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1, 1.0)
    }

}
#endif
