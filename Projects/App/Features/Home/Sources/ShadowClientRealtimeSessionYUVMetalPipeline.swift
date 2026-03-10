import CoreGraphics
import CoreVideo
import Foundation
import Metal
import simd

final class ShadowClientRealtimeSessionYUVMetalPipeline {
    struct CSCParameters {
        var row0: SIMD3<Float>
        var row1: SIMD3<Float>
        var row2: SIMD3<Float>
        var offsets: SIMD3<Float>
    }

    struct Vertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
    }

    private enum Constants {
        static let bt601 = (
            SIMD3<Float>(1.0, 0.0, 1.4020),
            SIMD3<Float>(1.0, -0.3441, -0.7141),
            SIMD3<Float>(1.0, 1.7720, 0.0)
        )
        static let bt709 = (
            SIMD3<Float>(1.0, 0.0, 1.5748),
            SIMD3<Float>(1.0, -0.1873, -0.4681),
            SIMD3<Float>(1.0, 1.8556, 0.0)
        )
        static let bt2020 = (
            SIMD3<Float>(1.0, 0.0, 1.4746),
            SIMD3<Float>(1.0, -0.1646, -0.5714),
            SIMD3<Float>(1.0, 1.8814, 0.0)
        )
    }

    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache

    init?(device: MTLDevice, colorPixelFormat: MTLPixelFormat) {
        self.device = device

        let bundle = Bundle(for: ShadowClientRealtimeSessionYUVMetalBundleMarker.self)
        guard let library = try? device.makeDefaultLibrary(bundle: bundle) else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "shadowYUVVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "shadowYUVBiplanarFragment")
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat

        guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            return nil
        }
        self.pipelineState = pipelineState

        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let textureCache
        else {
            return nil
        }
        self.textureCache = textureCache
    }

    func canRender(_ pixelBuffer: CVPixelBuffer) -> Bool {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return true
        default:
            return false
        }
    }

    func render(
        pixelBuffer: CVPixelBuffer,
        into renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        drawableSize: CGSize
    ) -> Bool {
        guard canRender(pixelBuffer),
              let lumaTextureRef = makeTexture(
                from: pixelBuffer,
                planeIndex: 0,
                pixelFormat: lumaTextureFormat(for: pixelBuffer)
              ),
              let chromaTextureRef = makeTexture(
                from: pixelBuffer,
                planeIndex: 1,
                pixelFormat: chromaTextureFormat(for: pixelBuffer)
              ),
              let lumaTexture = CVMetalTextureGetTexture(lumaTextureRef),
              let chromaTexture = CVMetalTextureGetTexture(chromaTextureRef),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              )
        else {
            return false
        }

        let vertices = vertexData(
            videoSize: CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ),
            drawableSize: drawableSize
        )
        var parameters = cscParameters(for: pixelBuffer)

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBytes(
            vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            index: 0
        )
        renderEncoder.setFragmentTexture(lumaTexture, index: 0)
        renderEncoder.setFragmentTexture(chromaTexture, index: 1)
        renderEncoder.setFragmentBytes(
            &parameters,
            length: MemoryLayout<CSCParameters>.stride,
            index: 0
        )
        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: vertices.count
        )
        renderEncoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            _ = lumaTextureRef
            _ = chromaTextureRef
        }
        return true
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        planeIndex: Int,
        pixelFormat: MTLPixelFormat
    ) -> CVMetalTexture? {
        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex),
            CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex),
            planeIndex,
            &textureRef
        )
        guard status == kCVReturnSuccess else {
            return nil
        }
        return textureRef
    }

    private func lumaTextureFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return .r16Unorm
        default:
            return .r8Unorm
        }
    }

    private func chromaTextureFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return .rg16Unorm
        default:
            return .rg8Unorm
        }
    }

    private func cscParameters(for pixelBuffer: CVPixelBuffer) -> CSCParameters {
        let matrix = cscMatrix(for: pixelBuffer)
        let fullRange = isFullRange(pixelBuffer)
        let bitDepth = bitsPerChannel(for: pixelBuffer)
        let channelRange = Float((1 << bitDepth) - 1)
        let yMin = fullRange ? 0.0 : Float(16 << (bitDepth - 8))
        let yMax = fullRange ? channelRange : Float(235 << (bitDepth - 8))
        let uvMin = fullRange ? 0.0 : Float(16 << (bitDepth - 8))
        let uvMax = fullRange ? channelRange : Float(240 << (bitDepth - 8))
        let yScale = channelRange / max(1, (yMax - yMin))
        let uvScale = channelRange / max(1, (uvMax - uvMin))

        return CSCParameters(
            row0: SIMD3<Float>(matrix.0.x * yScale, matrix.0.y * uvScale, matrix.0.z * uvScale),
            row1: SIMD3<Float>(matrix.1.x * yScale, matrix.1.y * uvScale, matrix.1.z * uvScale),
            row2: SIMD3<Float>(matrix.2.x * yScale, matrix.2.y * uvScale, matrix.2.z * uvScale),
            offsets: SIMD3<Float>(
                yMin / channelRange,
                Float(1 << (bitDepth - 1)) / channelRange,
                Float(1 << (bitDepth - 1)) / channelRange
            )
        )
    }

    private func cscMatrix(for pixelBuffer: CVPixelBuffer) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        let value = attachmentStringValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        )?.uppercased() ?? ""

        if value.contains("2020") {
            return Constants.bt2020
        }
        if value.contains("709") {
            return Constants.bt709
        }
        return Constants.bt601
    }

    private func isFullRange(_ pixelBuffer: CVPixelBuffer) -> Bool {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return true
        default:
            return false
        }
    }

    private func bitsPerChannel(for pixelBuffer: CVPixelBuffer) -> Int {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            return 10
        default:
            return 8
        }
    }

    private func vertexData(
        videoSize: CGSize,
        drawableSize: CGSize
    ) -> [Vertex] {
        let widthScale = drawableSize.width / max(videoSize.width, 1)
        let heightScale = drawableSize.height / max(videoSize.height, 1)
        let scale = min(widthScale, heightScale)
        let scaledWidth = videoSize.width * scale
        let scaledHeight = videoSize.height * scale
        let originX = (drawableSize.width - scaledWidth) * 0.5
        let originY = (drawableSize.height - scaledHeight) * 0.5

        let left = Float((originX / drawableSize.width) * 2.0 - 1.0)
        let right = Float(((originX + scaledWidth) / drawableSize.width) * 2.0 - 1.0)
        let top = Float(1.0 - (originY / drawableSize.height) * 2.0)
        let bottom = Float(1.0 - ((originY + scaledHeight) / drawableSize.height) * 2.0)

        return [
            Vertex(position: SIMD2<Float>(left, bottom), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD2<Float>(left, top), texCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD2<Float>(right, bottom), texCoord: SIMD2<Float>(1, 1)),
            Vertex(position: SIMD2<Float>(right, top), texCoord: SIMD2<Float>(1, 0)),
        ]
    }

    private func attachmentStringValue(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> String? {
        guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
            return nil
        }
        return attachment as? String
    }
}

private final class ShadowClientRealtimeSessionYUVMetalBundleMarker {}
