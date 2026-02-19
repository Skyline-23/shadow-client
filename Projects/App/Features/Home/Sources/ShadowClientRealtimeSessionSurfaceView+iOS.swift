import SwiftUI

#if os(iOS) || os(tvOS)
import CoreImage
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
                frameStore: surfaceContext.frameStore
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
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = ShadowClientStreamingLaunchBounds.defaultFPS
        view.delegate = renderer
        context.coordinator.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if let view = uiView as? MTKView {
            view.isPaused = false
        } else {
            uiView.backgroundColor = .black
        }
    }
}

final class ShadowClientRealtimeSessionMetalRenderer: NSObject, MTKViewDelegate {
    private let frameStore: ShadowClientRealtimeSessionFrameStore
    private let commandQueue: MTLCommandQueue
    private let ciContext: CIContext
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

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
                colorSpace: colorSpace
            )
        } else if let renderPass = view.currentRenderPassDescriptor,
                  let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass)
        {
            encoder.endEncoding()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
#endif
