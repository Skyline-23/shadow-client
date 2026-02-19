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
            ? ShadowClientRTSPAnnounceProfile.fallbackHostAddress
            : hostAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuredBitrateKbps = videoConfiguration.bitrateKbps
        let adjustedBitrateKbps = max(
            ShadowClientRTSPAnnounceDefaults.minimumBitrateKbps,
            min(
                ShadowClientRTSPAnnounceDefaults.maximumBitrateKbps,
                Int(Double(configuredBitrateKbps) * ShadowClientRTSPAnnounceDefaults.bitrateScale)
            )
        )

        let bitStreamFormat = ShadowClientRTSPAnnounceProfile.bitStreamFormat(for: codec)
        let hevcSupport = ShadowClientRTSPAnnounceProfile.hevcSupport(for: codec)
        let reliableUDPMode = ShadowClientRTSPAnnounceProfile.reliableUDPMode(
            encryptionEnabledFlags: encryptionEnabledFlags
        )
        let nvFeatureFlags = ShadowClientRTSPAnnounceProfile.negotiatedNVFeatureFlags(
            encryptionEnabledFlags: encryptionEnabledFlags
        )
        let refreshRateX100 = ShadowClientRTSPAnnounceProfile.refreshRateX100(
            for: videoConfiguration.fps
        )
        let surroundEnabled = videoConfiguration.enableSurroundAudio

        let attributes: [(String, String)] = [
            ("x-ml-general.featureFlags", "\(moonlightFeatureFlags)"),
            ("x-ss-general.encryptionEnabled", "\(encryptionEnabledFlags)"),
            ("x-ss-video[0].chromaSamplingType", ShadowClientRTSPAnnounceProfile.chromaSamplingType(yuv444Enabled: videoConfiguration.enableYUV444)),
            ("x-nv-video[0].clientViewportWd", "\(videoConfiguration.width)"),
            ("x-nv-video[0].clientViewportHt", "\(videoConfiguration.height)"),
            ("x-nv-video[0].maxFPS", "\(videoConfiguration.fps)"),
            ("x-nv-video[0].packetSize", ShadowClientRTSPAnnounceProfile.packetSize),
            ("x-nv-video[0].rateControlMode", ShadowClientRTSPAnnounceProfile.rateControlMode),
            ("x-nv-video[0].timeoutLengthMs", ShadowClientRTSPAnnounceProfile.timeoutLengthMs),
            ("x-nv-video[0].framesWithInvalidRefThreshold", ShadowClientRTSPAnnounceProfile.invalidReferenceThreshold),
            ("x-nv-video[0].initialBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-nv-video[0].initialPeakBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-nv-vqos[0].bw.minimumBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-nv-vqos[0].bw.maximumBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-ml-video.configuredBitrateKbps", "\(configuredBitrateKbps)"),
            ("x-nv-vqos[0].fec.enable", ShadowClientRTSPAnnounceProfile.fecEnabled),
            ("x-nv-vqos[0].videoQualityScoreUpdateTime", ShadowClientRTSPAnnounceProfile.qualityScoreUpdateTimeMs),
            ("x-nv-vqos[0].qosTrafficType", ShadowClientRTSPAnnounceProfile.videoQoSTrafficType),
            ("x-nv-aqos.qosTrafficType", ShadowClientRTSPAnnounceProfile.audioQoSTrafficType),
            ("x-nv-general.featureFlags", "\(nvFeatureFlags)"),
            ("x-nv-general.useReliableUdp", reliableUDPMode),
            ("x-nv-vqos[0].fec.minRequiredFecPackets", ShadowClientRTSPAnnounceProfile.fecMinimumRequiredPackets),
            ("x-nv-vqos[0].bllFec.enable", ShadowClientRTSPAnnounceProfile.bllFecEnabled),
            ("x-nv-vqos[0].drc.enable", ShadowClientRTSPAnnounceProfile.drcEnabled),
            ("x-nv-general.enableRecoveryMode", ShadowClientRTSPAnnounceProfile.recoveryModeEnabled),
            ("x-nv-video[0].videoEncoderSlicesPerFrame", ShadowClientRTSPAnnounceProfile.encoderSlicesPerFrame),
            ("x-nv-clientSupportHevc", hevcSupport),
            ("x-nv-vqos[0].bitStreamFormat", bitStreamFormat),
            ("x-nv-video[0].dynamicRangeMode", ShadowClientRTSPAnnounceProfile.dynamicRangeMode(hdrEnabled: videoConfiguration.enableHDR)),
            ("x-nv-video[0].maxNumReferenceFrames", ShadowClientRTSPAnnounceProfile.maxReferenceFrames),
            ("x-nv-video[0].clientRefreshRateX100", refreshRateX100),
            ("x-nv-audio.surround.numChannels", ShadowClientRTSPAnnounceProfile.audioNumChannels(surroundEnabled: surroundEnabled)),
            ("x-nv-audio.surround.channelMask", ShadowClientRTSPAnnounceProfile.audioChannelMask(surroundEnabled: surroundEnabled)),
            ("x-nv-audio.surround.enable", ShadowClientRTSPAnnounceProfile.surroundEnabledValue(surroundEnabled: surroundEnabled)),
            ("x-nv-audio.surround.AudioQuality", ShadowClientRTSPAnnounceProfile.surroundAudioQuality(surroundEnabled: surroundEnabled)),
            ("x-nv-aqos.packetDuration", ShadowClientRTSPAnnounceProfile.aqosPacketDuration),
            ("x-nv-video[0].encoderCscMode", ShadowClientRTSPAnnounceProfile.encoderCSCMode),
        ]

        var payload = ""
        payload += "v=\(ShadowClientRTSPAnnounceProfile.sdpVersion)\r\n"
        payload += "o=\(ShadowClientRTSPAnnounceProfile.sdpOriginUsername) \(ShadowClientRTSPAnnounceProfile.sdpOriginSessionID) \(ShadowClientRTSPAnnounceProfile.sdpOriginSessionVersion) \(ShadowClientRTSPAnnounceProfile.sdpOriginNetworkType) \(ShadowClientRTSPAnnounceProfile.sdpOriginAddressType) \(safeHost)\r\n"
        payload += "s=\(ShadowClientRTSPAnnounceProfile.sdpSessionName)\r\n"
        for (name, value) in attributes {
            payload += "a=\(name):\(value) \r\n"
        }
        payload += "t=\(ShadowClientRTSPAnnounceProfile.sdpTiming)\r\n"
        payload += "m=\(ShadowClientRTSPAnnounceProfile.sdpMediaNameVideo) \(videoPort)  \r\n"
        return Data(payload.utf8)
    }
}
