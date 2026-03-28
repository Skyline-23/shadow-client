import Foundation

enum ShadowClientRTSPAnnouncePayloadBuilder {
    static func build(
        hostAddress: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration,
        codec: ShadowClientVideoCodec,
        videoPort: UInt16,
        moonlightFeatureFlags: UInt32,
        encryptionEnabledFlags: UInt32,
        clientDisplayCharacteristics: ShadowClientApolloClientDisplayCharacteristics
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
        let requestedDynamicRangeTransport = clientDisplayCharacteristics
            .requestedDynamicRangeTransport(hdrRequested: videoConfiguration.enableHDR)
            .rawValue
        let supportsFrameGatedHDR = ShadowClientApolloSinkContractProfile.boolString(
            clientDisplayCharacteristics.supportsFrameGatedHDR
        )
        let supportsHDRTileOverlay = ShadowClientApolloSinkContractProfile.boolString(
            clientDisplayCharacteristics.supportsHDRTileOverlay
        )
        let supportsPerFrameHDRMetadata = ShadowClientApolloSinkContractProfile.boolString(
            clientDisplayCharacteristics.supportsPerFrameHDRMetadata
        )
        let sinkModeIsLogical = ShadowClientApolloSinkContractProfile.boolString(
            clientDisplayCharacteristics.modeIsLogical
        )

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
            ("x-apollo-video[0].clientDisplayGamut", clientDisplayCharacteristics.gamut.rawValue),
            ("x-apollo-video[0].clientDisplayTransfer", clientDisplayCharacteristics.transfer.rawValue),
            ("x-apollo-video[0].clientDisplayScalePercent", "\(clientDisplayCharacteristics.scalePercent)"),
            ("x-apollo-video[0].clientDisplayHiDPI", clientDisplayCharacteristics.hiDPIEnabled ? "1" : "0"),
            ("x-apollo-video[0].clientDisplayCurrentEDRHeadroom", "\(clientDisplayCharacteristics.currentEDRHeadroom)"),
            ("x-apollo-video[0].clientDisplayPotentialEDRHeadroom", "\(clientDisplayCharacteristics.potentialEDRHeadroom)"),
            ("x-apollo-video[0].clientDisplayCurrentPeakLuminanceNits", "\(clientDisplayCharacteristics.currentPeakLuminanceNits)"),
            ("x-apollo-video[0].clientDisplayPotentialPeakLuminanceNits", "\(clientDisplayCharacteristics.potentialPeakLuminanceNits)"),
            ("x-shadow-general.featureFlags", "\(ShadowClientRTSPAnnounceProfile.nvFeatureFlagsBase)"),
            ("x-shadow-general.useReliableUdp", reliableUDPMode),
            ("x-shadow-general.transportFeatureFlags", "\(moonlightFeatureFlags)"),
            ("x-shadow-general.encryptionEnabled", "\(encryptionEnabledFlags)"),
            ("x-shadow-video[0].clientViewportWidth", "\(videoConfiguration.width)"),
            ("x-shadow-video[0].clientViewportHeight", "\(videoConfiguration.height)"),
            ("x-shadow-video[0].maxFPS", "\(videoConfiguration.fps)"),
            ("x-shadow-video[0].packetSize", ShadowClientRTSPAnnounceProfile.packetSize),
            ("x-shadow-video[0].maximumBitrateKbps", "\(adjustedBitrateKbps)"),
            ("x-shadow-video[0].configuredBitrateKbps", "\(configuredBitrateKbps)"),
            ("x-shadow-video[0].encoderSlicesPerFrame", ShadowClientRTSPAnnounceProfile.encoderSlicesPerFrame),
            ("x-shadow-video[0].maxReferenceFrames", ShadowClientRTSPAnnounceProfile.maxReferenceFrames),
            ("x-shadow-video[0].encoderCscMode", ShadowClientRTSPAnnounceProfile.encoderCSCMode),
            ("x-shadow-video[0].bitStreamFormat", bitStreamFormat),
            ("x-shadow-video[0].chromaSamplingType", ShadowClientRTSPAnnounceProfile.chromaSamplingType(yuv444Enabled: videoConfiguration.enableYUV444)),
            ("x-shadow-video[0].intraRefresh", ShadowClientRTSPAnnounceProfile.intraRefreshDisabled),
            ("x-shadow-video[0].qosTrafficType", ShadowClientRTSPAnnounceProfile.videoQoSTrafficType),
            ("x-shadow-video[0].fec.minRequiredPackets", ShadowClientRTSPAnnounceProfile.shadowFECMinimumRequiredPackets),
            ("x-shadow-audio.packetDuration", ShadowClientRTSPAnnounceProfile.aqosPacketDuration),
            ("x-shadow-audio.qosTrafficType", ShadowClientRTSPAnnounceProfile.audioQoSTrafficType),
            ("x-shadow-audio.surround.numChannels", ShadowClientRTSPAnnounceProfile.audioNumChannels(surroundEnabled: surroundEnabled)),
            ("x-shadow-audio.surround.channelMask", ShadowClientRTSPAnnounceProfile.audioChannelMask(surroundEnabled: surroundEnabled)),
            ("x-shadow-audio.surround.quality", ShadowClientRTSPAnnounceProfile.surroundAudioQuality(surroundEnabled: surroundEnabled)),
            ("x-shadow-sink.scalePercent", "\(clientDisplayCharacteristics.scalePercent)"),
            ("x-shadow-sink.hidpi", ShadowClientApolloSinkContractProfile.boolString(clientDisplayCharacteristics.hiDPIEnabled)),
            ("x-shadow-sink.modeIsLogical", sinkModeIsLogical),
            ("x-shadow-sink.gamut", clientDisplayCharacteristics.gamut.rawValue),
            ("x-shadow-sink.transfer", clientDisplayCharacteristics.transfer.rawValue),
            ("x-shadow-sink.currentEDRHeadroom", "\(clientDisplayCharacteristics.currentEDRHeadroom)"),
            ("x-shadow-sink.potentialEDRHeadroom", "\(clientDisplayCharacteristics.potentialEDRHeadroom)"),
            ("x-shadow-sink.currentPeakLuminanceNits", "\(clientDisplayCharacteristics.currentPeakLuminanceNits)"),
            ("x-shadow-sink.potentialPeakLuminanceNits", "\(clientDisplayCharacteristics.potentialPeakLuminanceNits)"),
            ("x-shadow-sink.requestedDynamicRangeTransport", requestedDynamicRangeTransport),
            ("x-shadow-sink.supportsFrameGatedHDR", supportsFrameGatedHDR),
            ("x-shadow-sink.supportsHDRTileOverlay", supportsHDRTileOverlay),
            ("x-shadow-sink.supportsPerFrameHDRMetadata", supportsPerFrameHDRMetadata),
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
