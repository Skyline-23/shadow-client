import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("RTSP ANNOUNCE payload uses propagated launch bitrate values")
func rtspAnnouncePayloadUsesPropagatedBitrateValues() {
    let payload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.5",
        videoConfiguration: .init(
            width: 2560,
            height: 1440,
            fps: 120,
            bitrateKbps: 48_000,
            preferredCodec: .h265,
            enableHDR: false,
            enableSurroundAudio: false,
            enableYUV444: false
        ),
        codec: .h265,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0
    )

    let attributes = rtspAnnounceAttributes(from: payload)

    #expect(attributes["x-ml-video.configuredBitrateKbps"] == "48000")
    #expect(attributes["x-nv-video[0].initialBitrateKbps"] == "48000")
    #expect(attributes["x-nv-video[0].initialPeakBitrateKbps"] == "48000")
    #expect(attributes["x-nv-vqos[0].bw.minimumBitrateKbps"] == "48000")
    #expect(attributes["x-nv-vqos[0].bw.maximumBitrateKbps"] == "48000")
}

@Test("RTSP ANNOUNCE payload maps HDR and YUV444 launch settings")
func rtspAnnouncePayloadMapsHdrAndYUV444() {
    let hdrYuvPayload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.6",
        videoConfiguration: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 20_000,
            preferredCodec: .h265,
            enableHDR: true,
            enableSurroundAudio: false,
            enableYUV444: true
        ),
        codec: .h265,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0
    )

    let sdr420Payload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.7",
        videoConfiguration: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 20_000,
            preferredCodec: .h265,
            enableHDR: false,
            enableSurroundAudio: false,
            enableYUV444: false
        ),
        codec: .h265,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0
    )

    let hdrYuvAttributes = rtspAnnounceAttributes(from: hdrYuvPayload)
    let sdr420Attributes = rtspAnnounceAttributes(from: sdr420Payload)

    #expect(hdrYuvAttributes["x-nv-video[0].dynamicRangeMode"] == "1")
    #expect(hdrYuvAttributes["x-ss-video[0].chromaSamplingType"] == "1")
    #expect(sdr420Attributes["x-nv-video[0].dynamicRangeMode"] == "0")
    #expect(sdr420Attributes["x-ss-video[0].chromaSamplingType"] == "0")
}

@Test("RTSP ANNOUNCE payload maps surround launch settings to audio fields")
func rtspAnnouncePayloadMapsSurroundAudio() {
    let surroundPayload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.8",
        videoConfiguration: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 20_000,
            preferredCodec: .h264,
            enableHDR: false,
            enableSurroundAudio: true,
            enableYUV444: false
        ),
        codec: .h264,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0
    )

    let stereoPayload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.9",
        videoConfiguration: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 20_000,
            preferredCodec: .h264,
            enableHDR: false,
            enableSurroundAudio: false,
            enableYUV444: false
        ),
        codec: .h264,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0
    )

    let surroundAttributes = rtspAnnounceAttributes(from: surroundPayload)
    let stereoAttributes = rtspAnnounceAttributes(from: stereoPayload)

    #expect(surroundAttributes["x-nv-audio.surround.numChannels"] == "6")
    #expect(surroundAttributes["x-nv-audio.surround.channelMask"] == "63")
    #expect(surroundAttributes["x-nv-audio.surround.enable"] == "1")
    #expect(surroundAttributes["x-nv-audio.surround.AudioQuality"] == "0")
    #expect(stereoAttributes["x-nv-audio.surround.numChannels"] == "2")
    #expect(stereoAttributes["x-nv-audio.surround.channelMask"] == "3")
    #expect(stereoAttributes["x-nv-audio.surround.enable"] == "0")
    #expect(stereoAttributes["x-nv-audio.surround.AudioQuality"] == "0")
}

@Test("RTSP ANNOUNCE payload includes legacy control channel hint for plaintext reliable UDP")
func rtspAnnouncePayloadIncludesLegacyControlChannelHint() {
    let payload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.10",
        videoConfiguration: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 20_000,
            preferredCodec: .av1,
            enableHDR: false,
            enableSurroundAudio: false,
            enableYUV444: false
        ),
        codec: .av1,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0
    )

    let attributes = rtspAnnounceAttributes(from: payload)

    #expect(attributes["x-nv-general.useReliableUdp"] == "1")
    #expect(attributes["x-nv-ri.useControlChannel"] == "1")
    #expect(attributes["x-nv-general.featureFlags"] == "135")
}

@Test("RTSP ANNOUNCE payload omits legacy control channel hint for encrypted control-v2 mode")
func rtspAnnouncePayloadOmitsLegacyControlChannelHintWhenEncryptedControlIsEnabled() {
    let payload = ShadowClientRTSPAnnouncePayloadBuilder.build(
        hostAddress: "192.168.1.11",
        videoConfiguration: .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 20_000,
            preferredCodec: .h265,
            enableHDR: false,
            enableSurroundAudio: false,
            enableYUV444: false
        ),
        codec: .h265,
        videoPort: 47_998,
        moonlightFeatureFlags: 3,
        encryptionEnabledFlags: 0x01
    )

    let attributes = rtspAnnounceAttributes(from: payload)

    #expect(attributes["x-nv-general.useReliableUdp"] == "13")
    #expect(attributes["x-nv-ri.useControlChannel"] == nil)
}

private func rtspAnnounceAttributes(from payload: Data) -> [String: String] {
    guard let text = String(data: payload, encoding: .utf8) else {
        return [:]
    }

    var attributes: [String: String] = [:]
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedLine.hasPrefix("a=") else {
            continue
        }
        let attribute = trimmedLine.dropFirst(2)
        guard let separator = attribute.firstIndex(of: ":") else {
            continue
        }

        let key = String(attribute[..<separator]).trimmingCharacters(in: .whitespaces)
        let value = String(attribute[attribute.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        attributes[key] = value
    }

    return attributes
}
