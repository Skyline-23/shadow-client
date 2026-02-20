import SwiftUI

#if os(macOS)
import AppKit
import CoreImage
import MetalKit

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
                frameStore: surfaceContext.frameStore
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
        view.preferredFramesPerSecond = ShadowClientStreamingLaunchBounds.defaultFPS
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let view = nsView as? MTKView {
            view.isPaused = false
        } else {
            nsView.wantsLayer = true
            nsView.layer?.backgroundColor = NSColor.black.cgColor
        }
    }
}

final class ShadowClientRealtimeSessionMetalRenderer: NSObject, MTKViewDelegate {
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext

    init?(
        device: MTLDevice,
        frameStore: ShadowClientRealtimeSessionFrameStore
    ) {
        guard let commandQueue = device.makeCommandQueue() else {
            return nil
        }
        self.frameStore = frameStore
        self.commandQueue = commandQueue
        self.ciContext = CIContext(mtlDevice: device)
        super.init()
    }

    func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        if let pixelBuffer = frameStore.snapshot() {
            let colorConfiguration = ShadowClientRealtimeSessionColorPipeline.configuration(for: pixelBuffer)
            applyColorConfiguration(colorConfiguration, to: view)
            let sourceImage = CIImage(cvPixelBuffer: pixelBuffer)
            let drawableRect = CGRect(origin: .zero, size: view.drawableSize)
            let sourceRect = sourceImage.extent
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

            let transformed = sourceImage
                .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: offset.x, y: offset.y))

            ciContext.render(
                transformed,
                to: drawable.texture,
                commandBuffer: commandBuffer,
                bounds: drawableRect,
                colorSpace: colorConfiguration.displayColorSpace
            )
        } else if let renderPass = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        {
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private func applyColorConfiguration(
        _ configuration: ShadowClientRealtimeSessionColorConfiguration,
        to view: MTKView
    ) {
        if view.colorPixelFormat != configuration.pixelFormat {
            view.colorPixelFormat = configuration.pixelFormat
        }
        view.colorspace = configuration.displayColorSpace

        if #available(macOS 10.15, *),
           let metalLayer = view.layer as? CAMetalLayer
        {
            metalLayer.wantsExtendedDynamicRangeContent = configuration.prefersExtendedDynamicRange
        }
    }
}
#endif
