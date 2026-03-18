import ShadowClientStreaming
import ShadowUIFoundation
import ShadowClientFeatureSession

enum ShadowClientLaunchSettingsKit {
    static func resolvedLaunchSettings(
        currentSettings: ShadowClientAppSettings,
        selectedResolution: ShadowClientStreamingResolutionPreset,
        hostApp: ShadowClientRemoteAppDescriptor?,
        networkSignal: StreamingNetworkSignal?,
        localHDRDisplayAvailable: Bool,
        viewportMetrics: ShadowClientLaunchViewportMetrics,
        displayMetrics: ShadowClientDisplayMetricsState
    ) -> ShadowClientGameStreamLaunchSettings {
        let base = currentSettings.launchSettings(
            hostApp: hostApp,
            networkSignal: networkSignal,
            localHDRDisplayAvailable: localHDRDisplayAvailable
        )
        guard selectedResolution == .retinaAuto else {
            return base
        }

        let launchGeometry = ShadowClientDisplayMetricsKit.resolveLaunchGeometry(
            viewportMetrics: viewportMetrics,
            displayMetrics: displayMetrics
        )
        let launchSize = launchGeometry.renderSize
        let launchScalePercent = ShadowClientDisplayMetricsPlatformKit.launchRequestScalePercent(
            from: launchGeometry
        )
        return .init(
            width: Int(launchSize.width),
            height: Int(launchSize.height),
            fps: base.fps,
            bitrateKbps: base.bitrateKbps,
            preferredCodec: base.preferredCodec,
            enableHDR: base.enableHDR,
            enableSurroundAudio: base.enableSurroundAudio,
            preferredSurroundChannelCount: base.preferredSurroundChannelCount,
            lowLatencyMode: base.lowLatencyMode,
            enableVSync: base.enableVSync,
            enableFramePacing: base.enableFramePacing,
            enableYUV444: base.enableYUV444,
            unlockBitrateLimit: base.unlockBitrateLimit,
            forceHardwareDecoding: base.forceHardwareDecoding,
            resolutionScalePercent: launchScalePercent,
            requestHiDPI: launchScalePercent > 100,
            preferVirtualDisplay: base.preferVirtualDisplay,
            optimizeGameSettingsForStreaming: base.optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStreamEnds: base.quitAppOnHostAfterStreamEnds,
            playAudioOnHost: base.playAudioOnHost
        )
    }
}
