#if os(macOS)
@preconcurrency import AVFoundation
import CoreAudio
import Foundation

enum ShadowClientAudioOutputCapabilityPlatformKit {
    static func supportsHeadTrackedRoute() -> Bool {
        false
    }

    static func prefersSpatialHeadphoneRendering(channels: Int) async -> Bool {
        _ = channels
        return false
    }

    static func maximumOutputChannels() async -> Int {
        if let outputChannels = macDefaultOutputChannelCount(), outputChannels > 0 {
            return max(2, outputChannels)
        }

        let engine = AVAudioEngine()
        let outputChannels = Int(engine.outputNode.inputFormat(forBus: 0).channelCount)
        if outputChannels > 0 {
            return outputChannels
        }

        let mixerChannels = Int(engine.mainMixerNode.outputFormat(forBus: 0).channelCount)
        if mixerChannels > 0 {
            return mixerChannels
        }
        return 2
    }

    @MainActor
    static func currentMaximumOutputChannels() -> Int {
        if let outputChannels = macDefaultOutputChannelCount(), outputChannels > 0 {
            return max(2, outputChannels)
        }

        let engine = AVAudioEngine()
        let outputChannels = Int(engine.outputNode.inputFormat(forBus: 0).channelCount)
        if outputChannels > 0 {
            return outputChannels
        }

        let mixerChannels = Int(engine.mainMixerNode.outputFormat(forBus: 0).channelCount)
        if mixerChannels > 0 {
            return mixerChannels
        }
        return 2
    }

    static func currentRouteSummary() -> String {
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        return "default-output{channels=\(outputFormat.channelCount),sampleRate=\(Int(outputFormat.sampleRate))}"
    }

    static func currentRenderingSummary() -> String {
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        return "engine-output{channels=\(outputFormat.channelCount),sampleRate=\(Int(outputFormat.sampleRate))}"
    }

    private static func macDefaultOutputChannelCount() -> Int? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )
        guard deviceStatus == noErr, defaultDeviceID != 0 else {
            return nil
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var configurationSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            defaultDeviceID,
            &address,
            0,
            nil,
            &configurationSize
        )
        guard sizeStatus == noErr, configurationSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return nil
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(configurationSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        let bufferListPointer = rawBuffer.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )

        let configurationStatus = AudioObjectGetPropertyData(
            defaultDeviceID,
            &address,
            0,
            nil,
            &configurationSize,
            bufferListPointer
        )
        guard configurationStatus == noErr else {
            return nil
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let channelCount = bufferList.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
        }
        return channelCount > 0 ? channelCount : nil
    }
}
#endif
