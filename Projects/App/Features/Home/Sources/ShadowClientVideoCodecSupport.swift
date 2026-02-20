import CoreMedia
import Foundation
import VideoToolbox

public struct ShadowClientVideoCodecSupport: Sendable {
    public typealias HardwareDecoderSupport = @Sendable (CMVideoCodecType) -> Bool

    private static let defaultHardwareDecoderSupport: HardwareDecoderSupport = { codecType in
        if codecType == kCMVideoCodecType_AV1 {
            if #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) {
                return VTIsHardwareDecodeSupported(codecType)
            }
            return false
        }

        return VTIsHardwareDecodeSupported(codecType)
    }

    private let hardwareDecoderSupport: HardwareDecoderSupport

    public init(
        hardwareDecoderSupport: HardwareDecoderSupport? = nil
    ) {
        self.hardwareDecoderSupport = hardwareDecoderSupport ?? Self.defaultHardwareDecoderSupport
    }

    public func resolvePreferredCodec(
        _ preferredCodec: ShadowClientVideoCodecPreference,
        enableHDR: Bool = false,
        enableYUV444: Bool = false
    ) -> ShadowClientVideoCodecPreference {
        let av1Supported = hardwareDecoderSupport(kCMVideoCodecType_AV1) &&
            !enableYUV444
        let nonAV1Fallback: ShadowClientVideoCodecPreference = hardwareDecoderSupport(kCMVideoCodecType_HEVC) ? .h265 : .h264

        switch preferredCodec {
        case .auto:
            return av1Supported ? .auto : nonAV1Fallback
        case .av1:
            return av1Supported ? .av1 : nonAV1Fallback
        case .h265, .h264:
            return preferredCodec
        }
    }
}
