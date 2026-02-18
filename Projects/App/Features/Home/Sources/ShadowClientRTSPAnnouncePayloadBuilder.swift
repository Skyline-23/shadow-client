import Foundation

enum ShadowClientRTSPAnnouncePayloadBuilder {
    static func build(
        hostAddress: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration,
        codec: ShadowClientVideoCodec,
        videoPort: UInt16,
        moonlightFeatureFlags: UInt32,
        encryptionEnabledFlags: UInt32
    ) -> Data {
        let safeHost = hostAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "127.0.0.1"
            : hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuredBitrateKbps = 22_000
        let adjustedBitrateKbps = max(1_000, min(100_000, Int(Double(configuredBitrateKbps) * 0.80)))

        let bitStreamFormat: String
        let hevcSupport: String
        switch codec {
        case .av1:
            bitStreamFormat = "2"
            hevcSupport = "1"
        case .h265:
            bitStreamFormat = "1"
            hevcSupport = "1"
        case .h264:
            bitStreamFormat = "0"
            hevcSupport = "0"
        }

        let reliableUDPMode = (encryptionEnabledFlags & 0x01) != 0 ? "13" : "1"
        var nvFeatureFlags: UInt32 = 0x07
        if (encryptionEnabledFlags & 0x01) != 0 {
            nvFeatureFlags |= 0x80
        }
        if (encryptionEnabledFlags & 0x04) != 0 {
            nvFeatureFlags |= 0x20
        }

        let attributes: [(String, String)] = [
            ("x-ml-general.featureFlags", "\(moonlightFeatureFlags)"),
            ("x-ss-general.encryptionEnabled", "\(encryptionEnabledFlags)"),
            ("x-ss-video[0].chromaSamplingType", "0"),
            ("x-nv-video[0].clientViewportWd", "\(videoConfiguration.width)"),
            ("x-nv-video[0].clientViewportHt", "\(videoConfiguration.height)"),
            ("x-nv-video[0].maxFPS", "60"),
            ("x-nv-video[0].packetSize", "1392"),
            ("x-nv-video[0].rateControlMode", "4"),
            ("x-nv-video[0].timeoutLengthMs", "7000"),
            ("x-nv-video[0].framesWithInvalidRefThreshold", "0"),
            ("x-nv-video[0].initialBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-nv-video[0].initialPeakBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-nv-vqos[0].bw.minimumBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-nv-vqos[0].bw.maximumBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-ml-video.configuredBitrateKbps", "\(configuredBitrateKbps)"),
            ("x-nv-vqos[0].fec.enable", "1"),
            ("x-nv-vqos[0].videoQualityScoreUpdateTime", "5000"),
            ("x-nv-vqos[0].qosTrafficType", "5"),
            ("x-nv-aqos.qosTrafficType", "4"),
            ("x-nv-general.featureFlags", "\(nvFeatureFlags)"),
            ("x-nv-general.useReliableUdp", reliableUDPMode),
            ("x-nv-vqos[0].fec.minRequiredFecPackets", "2"),
            ("x-nv-vqos[0].bllFec.enable", "0"),
            ("x-nv-vqos[0].drc.enable", "0"),
            ("x-nv-general.enableRecoveryMode", "0"),
            ("x-nv-video[0].videoEncoderSlicesPerFrame", "1"),
            ("x-nv-clientSupportHevc", hevcSupport),
            ("x-nv-vqos[0].bitStreamFormat", bitStreamFormat),
            ("x-nv-video[0].dynamicRangeMode", "0"),
            ("x-nv-video[0].maxNumReferenceFrames", "0"),
            ("x-nv-video[0].clientRefreshRateX100", "6000"),
            ("x-nv-audio.surround.numChannels", "2"),
            ("x-nv-audio.surround.channelMask", "3"),
            ("x-nv-audio.surround.enable", "0"),
            ("x-nv-audio.surround.AudioQuality", "0"),
            ("x-nv-aqos.packetDuration", "5"),
            ("x-nv-video[0].encoderCscMode", "0"),
        ]

        var payload = ""
        payload += "v=0\r\n"
        payload += "o=android 0 14 IN IPv4 \(safeHost)\r\n"
        payload += "s=NVIDIA Streaming Client\r\n"
        for (name, value) in attributes {
            payload += "a=\(name):\(value) \r\n"
        }
        payload += "t=0 0\r\n"
        payload += "m=video \(videoPort)  \r\n"
        return Data(payload.utf8)
    }
}
