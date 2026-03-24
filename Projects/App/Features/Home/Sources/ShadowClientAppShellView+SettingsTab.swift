import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowUIFoundation
import ShadowClientFeatureSession

extension ShadowClientAppShellView {
    var settingsTab: some View {
        ZStack(alignment: .top) {
            backgroundGradient
            ScrollView {
                VStack(spacing: ShadowClientAppShellChrome.Metrics.settingsSectionSpacing) {
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
                                    Text(ShadowClientSettingsCopyKit.autoBitrateFootnote())
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
                            Text(ShadowClientSettingsCopyKit.hdrUnavailableFootnote())
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Color.white.opacity(0.7))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        settingsRow {
                            Toggle(isOn: $preferVirtualDisplay) {
                                Label("Prefer Apollo virtual display", systemImage: "display.2")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
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

                        #if os(iOS) || os(tvOS)
                        Text(ShadowClientSettingsCopyKit.mobileAudioRouteFootnote())
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        #endif

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
                                Text(ShadowClientSettingsCopyKit.clientPlaybackUnavailableFootnote())
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
                            Toggle(isOn: $prioritizeStreamingTraffic) {
                                Text("Prioritize streaming traffic on this device")
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
                            ForEach(
                                ShadowClientSettingsDiagnosticsPresentationKit.telemetryRows(
                                    settingsDiagnosticsModel
                                ),
                                id: \.label
                            ) { row in
                                diagnosticsRow(
                                    label: row.label,
                                    value: row.value,
                                    valueColor: ShadowClientSettingsDiagnosticsPresentationKit.valueColor(
                                        for: row,
                                        tone: settingsDiagnosticsModel.tone
                                    )
                                )
                            }
                        } else {
                            settingsRow {
                                Label(
                                    ShadowClientSettingsDiagnosticsPresentationKit.emptyTelemetryMessage(),
                                    systemImage: "antenna.radiowaves.left.and.right"
                                )
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    settingsSection(title: "Controller") {
                        settingsRow {
                            Label(
                                ShadowClientSettingsDiagnosticsPresentationKit.controllerContractMessage(),
                                systemImage: "gamecontroller.fill"
                            )
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
                .padding(.bottom, ShadowClientAppShellChrome.Metrics.screenBottomPadding)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("shadow.tab.settings")
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        .tag(AppTab.settings)
    }
}
