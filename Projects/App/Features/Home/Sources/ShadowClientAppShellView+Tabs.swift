import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

extension ShadowClientAppShellView {
var homeTab: some View {
        ZStack {
            backgroundGradient
            ScrollView {
                VStack(spacing: 28) {
                    remoteDesktopHostCard
                    connectionStatusCard

                    ShadowClientFeatureHomeView(
                        platformName: platformName,
                        dependencies: baseDependencies.applying(settings: currentSettings),
                        connectionState: connectionState,
                        showsDiagnosticsHUD: currentSettings.showDiagnosticsHUD
                    )
                    .id(currentSettings.streamingIdentityKey)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
        .accessibilityIdentifier("shadow.tab.home")
        .tabItem { Label("Home", systemImage: "house.fill") }
        .tag(AppTab.home)
    }

var settingsTab: some View {
        ZStack(alignment: .top) {
            backgroundGradient
            ScrollView {
                VStack(spacing: 18) {
                    settingsSection(title: "Client Connection") {
                        TextField("Host (IP or hostname)", text: $connectionHost)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(rowSurface(cornerRadius: 10))
                            .onSubmit {
                                if canConnect {
                                    connectToHost(autoLaunchAfterConnect: true)
                                }
                            }

                        settingsRow {
                            Label("Backend: \(baseDependencies.connectionBackendLabel)", systemImage: "bolt.horizontal.circle")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                            Spacer(minLength: 0)
                        }

                        settingsRow {
                            Label(
                                "Auto Discovery: \(autoFindHosts ? hostDiscoveryRuntime.state.label : "Disabled")",
                                systemImage: "dot.radiowaves.left.and.right"
                            )
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                            Spacer(minLength: 0)
                            Button {
                                hostDiscoveryRuntime.refresh()
                                refreshRemoteDesktopCatalog()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityIdentifier("shadow.settings.connection.refresh-discovery")
                            .accessibilityLabel("Refresh Discovered Hosts")
                            .buttonStyle(.bordered)
                            .disabled(!autoFindHosts)
                        }

                        if hostDiscoveryRuntime.hosts.isEmpty {
                            settingsRow {
                                Text("No hosts discovered yet. Keep this view open or enter host manually.")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                Spacer(minLength: 0)
                            }
                        } else {
                            ForEach(hostDiscoveryRuntime.hosts.prefix(8)) { discoveredHost in
                                discoveredHostRow(discoveredHost)
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Connect") {
                                connectToHost(autoLaunchAfterConnect: true)
                            }
                            .accessibilityIdentifier("shadow.settings.connection.connect")
                            .accessibilityLabel("Connect to Host")
                            .disabled(!canConnect)
                            .buttonStyle(.borderedProminent)

                            Button("Disconnect") {
                                disconnectFromHost()
                            }
                            .accessibilityIdentifier("shadow.settings.connection.disconnect")
                            .accessibilityLabel("Disconnect from Host")
                            .disabled(!canDisconnect)
                            .buttonStyle(.bordered)

                            Spacer(minLength: 0)
                        }

                        settingsRow {
                            Label(connectionStatusText, systemImage: connectionStatusSymbol)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(connectionStatusColor)
                            Spacer(minLength: 0)
                        }
                    }

                    settingsSection(title: "Basic Settings") {
                        settingsPickerRow(
                            title: "Resolution",
                            symbol: "rectangle.expand.vertical",
                            selection: Binding(
                                get: { selectedResolution },
                                set: { selectedResolution = $0 }
                            )
                        ) {
                            ForEach(ShadowClientStreamingResolutionPreset.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsPickerRow(
                            title: "Frame Rate",
                            symbol: "film.stack",
                            selection: Binding(
                                get: { selectedFrameRate },
                                set: { selectedFrameRate = $0 }
                            )
                        ) {
                            ForEach(ShadowClientStreamingFrameRatePreset.allCases, id: \.self) { option in
                                Text("\(option.rawValue) FPS").tag(option)
                            }
                        }

                        settingsRow {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $autoBitrate) {
                                    Text("Auto bitrate (recommended)")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .tint(.mint)

                                HStack {
                                    Label("Video bitrate", systemImage: "dial.medium")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Spacer(minLength: 8)
                                    Text("\(effectiveBitrateKbps) Kbps")
                                        .font(.footnote.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.mint)
                                }
                                Slider(
                                    value: bitrateSliderBinding,
                                    in: Double(ShadowClientStreamingLaunchBounds.minimumBitrateKbps)...maxBitrateKbps,
                                    step: Double(ShadowClientAppSettingsDefaults.bitrateStepKbps)
                                )
                                .tint(.mint)
                                .disabled(autoBitrate)
                                .opacity(autoBitrate ? 0.45 : 1.0)

                                if autoBitrate {
                                    Text("Estimated from resolution, frame rate, codec, HDR, and YUV444.")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(Color.white.opacity(0.7))
                                }
                            }
                        }

                        settingsPickerRow(
                            title: "Display mode",
                            symbol: "macwindow",
                            selection: Binding(
                                get: { selectedDisplayMode },
                                set: { selectedDisplayMode = $0 }
                            )
                        ) {
                            ForEach(ShadowClientDisplayMode.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $lowLatencyMode) {
                                Label("Low-Latency Mode", systemImage: "speedometer")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $preferHDR) {
                                Label("Enable HDR (Experimental)", systemImage: "sparkles.tv")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                            .disabled(!isLocalHDRDisplayAvailable)
                        }

                        if !isLocalHDRDisplayAvailable {
                            Text("HDR requires a real HDR/EDR display on this device.")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        settingsRow {
                            Toggle(isOn: $enableVSync) {
                                Label("V-Sync", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $enableFramePacing) {
                                Label("Frame pacing", systemImage: "waveform.path")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Audio Settings") {
                        settingsPickerRow(
                            title: "Audio configuration",
                            symbol: "hifispeaker.and.homepod.fill",
                            selection: Binding(
                                get: { selectedAudioConfiguration },
                                set: { selectedAudioConfiguration = $0 }
                            )
                        ) {
                            ForEach(ShadowClientAudioConfiguration.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsRow {
                            Toggle(
                                isOn: Binding(
                                    get: {
                                        ShadowClientAudioPlaybackDefaults.supportsClientPlayback
                                            ? muteHostSpeakersWhileStreaming
                                            : false
                                    },
                                    set: { newValue in
                                        muteHostSpeakersWhileStreaming = newValue
                                    }
                                )
                            ) {
                                Text("Mute host PC speakers while streaming")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                            .disabled(!ShadowClientAudioPlaybackDefaults.supportsClientPlayback)
                        }

                        if !ShadowClientAudioPlaybackDefaults.supportsClientPlayback {
                            settingsRow {
                                Text("Client audio playback is not available yet. Audio is currently routed to the host device.")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Color.white.opacity(0.72))
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $muteAudioWhenInactiveWindow) {
                                Text("Mute audio stream when app is not active")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Input Settings") {
                        settingsRow {
                            Toggle(isOn: $optimizeMouseForDesktop) {
                                Text("Optimize mouse for remote desktop instead of games")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $captureSystemKeyboardShortcuts) {
                                Text("Capture system keyboard shortcuts")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        if captureSystemKeyboardShortcuts {
                            settingsPickerRow(
                                title: "Shortcut capture mode",
                                symbol: "command",
                                selection: Binding(
                                    get: { selectedKeyboardShortcutCaptureMode },
                                    set: { selectedKeyboardShortcutCaptureMode = $0 }
                                )
                            ) {
                                ForEach(ShadowClientKeyboardShortcutCaptureMode.allCases, id: \.self) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $useTouchscreenTrackpad) {
                                Text("Use touchscreen as virtual trackpad")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $swapMouseButtons) {
                                Text("Swap left and right mouse buttons")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $reverseMouseScrollDirection) {
                                Text("Reverse mouse scrolling direction")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Gamepad Settings") {
                        settingsRow {
                            Toggle(isOn: $swapABXYButtons) {
                                Text("Swap A/B and X/Y gamepad buttons")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $forceGamepadOneAlwaysConnected) {
                                Text("Force gamepad #1 always connected")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $enableGamepadMouseMode) {
                                Text("Enable mouse control with gamepads by holding Start")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $processGamepadInputInBackground) {
                                Text("Process gamepad input while app is in background")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Advanced Settings") {
                        settingsPickerRow(
                            title: "Video decoder",
                            symbol: "cpu",
                            selection: Binding(
                                get: { selectedVideoDecoder },
                                set: { selectedVideoDecoder = $0 }
                            )
                        ) {
                            ForEach(ShadowClientVideoDecoderPreference.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsPickerRow(
                            title: "Video codec",
                            symbol: "film",
                            selection: Binding(
                                get: { selectedVideoCodec },
                                set: { selectedVideoCodec = $0 }
                            )
                        ) {
                            ForEach(ShadowClientVideoCodecPreference.allCases, id: \.self) { option in
                                Text(videoCodecLabel(option)).tag(option)
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $enableYUV444) {
                                Text("Enable YUV 4:4:4 (Experimental)")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $unlockBitrateLimit) {
                                Text("Unlock bitrate limit (Experimental)")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $autoFindHosts) {
                                Text("Automatically find PCs on local network")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Host Settings") {
                        settingsRow {
                            Toggle(isOn: $optimizeGameSettingsForStreaming) {
                                Text("Optimize game settings for streaming")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $quitAppOnHostAfterStream) {
                                Text("Quit app on host after ending stream")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "UI Settings") {
                        settingsPickerRow(
                            title: "Language",
                            symbol: "globe",
                            selection: Binding(
                                get: { selectedLanguage },
                                set: { selectedLanguage = $0 }
                            )
                        ) {
                            ForEach(ShadowClientLanguagePreference.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsPickerRow(
                            title: "GUI display mode",
                            symbol: "rectangle.3.group",
                            selection: Binding(
                                get: { selectedGUIDisplayMode },
                                set: { selectedGUIDisplayMode = $0 }
                            )
                        ) {
                            ForEach(ShadowClientGUIDisplayMode.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }

                    settingsSection(title: "Diagnostics") {
                        settingsRow {
                            Toggle(isOn: $showDiagnosticsHUD) {
                                Label("Show Debug HUD", systemImage: "waveform.path.ecg.rectangle")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Session Launch Plan") {
                        if let settingsDiagnosticsModel {
                            diagnosticsRow(
                                label: "Tone",
                                value: settingsDiagnosticsModel.tone.rawValue.uppercased(),
                                valueColor: toneColor(for: settingsDiagnosticsModel.tone)
                            )
                            diagnosticsRow(
                                label: "Target Buffer",
                                value: "\(settingsDiagnosticsModel.targetBufferMs) ms"
                            )
                            diagnosticsRow(
                                label: "Jitter / Packet Loss",
                                value: "\(settingsDiagnosticsModel.jitterMs) ms / \(String(format: "%.1f", settingsDiagnosticsModel.packetLossPercent))%"
                            )
                            diagnosticsRow(
                                label: "Frame Drop / AV Sync",
                                value: "\(String(format: "%.1f", settingsDiagnosticsModel.frameDropPercent))% / \(settingsDiagnosticsModel.avSyncOffsetMs) ms"
                            )
                            diagnosticsRow(
                                label: "Drop Origin",
                                value: "NET \(settingsDiagnosticsModel.networkDroppedFrames) / PACER \(settingsDiagnosticsModel.pacerDroppedFrames)"
                            )
                            diagnosticsRow(
                                label: "Telemetry Timestamp",
                                value: "\(settingsDiagnosticsModel.timestampMs) ms",
                                valueColor: Color.white.opacity(0.78)
                            )
                            if let sampleIntervalMs = settingsDiagnosticsModel.sampleIntervalMs {
                                diagnosticsRow(
                                    label: "Sample Interval",
                                    value: "\(sampleIntervalMs) ms",
                                    valueColor: Color.white.opacity(0.78)
                                )
                            } else {
                                diagnosticsRow(
                                    label: "Sample Interval",
                                    value: "--",
                                    valueColor: Color.white.opacity(0.78)
                                )
                            }
                            if settingsDiagnosticsModel.receivedOutOfOrderSample {
                                diagnosticsRow(
                                    label: "Sample Order",
                                    value: "Out-of-order telemetry sample ignored",
                                    valueColor: .orange
                                )
                            }
                            diagnosticsRow(
                                label: "Session Video / Audio",
                                value: "\(settingsDiagnosticsModel.hdrVideoMode.rawValue.uppercased()) / \(settingsDiagnosticsModel.audioMode.rawValue.uppercased())"
                            )
                            diagnosticsRow(
                                label: "Reconfigure",
                                value: "V:\(settingsDiagnosticsModel.shouldRenegotiateVideoPipeline ? "Y" : "N") A:\(settingsDiagnosticsModel.shouldRenegotiateAudioPipeline ? "Y" : "N") QDrop:\(settingsDiagnosticsModel.shouldApplyQualityDropImmediately ? "Y" : "N")",
                                valueColor: Color.white.opacity(0.78)
                            )
                            if settingsDiagnosticsModel.recoveryStableSamplesRemaining > 0 {
                                diagnosticsRow(
                                    label: "Recovery Hold",
                                    value: "\(settingsDiagnosticsModel.recoveryStableSamplesRemaining) stable sample(s) remaining",
                                    valueColor: .orange
                                )
                            }
                        } else {
                            settingsRow {
                                Label("Awaiting telemetry samples from active session.", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    settingsSection(title: "Controller") {
                        settingsRow {
                            Label("DualSense feedback contract follows Apple Game Controller capabilities.", systemImage: "gamecontroller.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("shadow.tab.settings")
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        .tag(AppTab.settings)
    }

}
