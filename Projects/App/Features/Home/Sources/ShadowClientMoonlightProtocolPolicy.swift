import Foundation

enum ShadowClientMoonlightProtocolPolicy {
    enum Audio {
        // Moonlight/Sunshine Opus + FEC RTP defaults.
        static let primaryPayloadType = 97
        static let fecWrapperPayloadType = 127
        static let dynamicPayloadTypeRange = 96 ... 127
        static let payloadTypeMask: UInt8 = 0x7F

        // Moonlight audio RS-FEC geometry: 4 data shards + 2 parity shards.
        static let fecDataShardsPerBlock = 4
        static let fecParityShardsPerBlock = 2
        static let fecHeaderLength = 12
        static let defaultTimestampStep: UInt32 = 5
        static let parityCoefficients: [[UInt8]] = [
            [0x77, 0x40, 0x38, 0x0E],
            [0xC7, 0xA7, 0x0D, 0x6C],
        ]

        // AQoS packet duration defaults and startup resync window.
        static let defaultPacketDurationMs = 5
        static let startupResyncWindowMs = 500
        static let packetQueueBound = 30
        // Moonlight renderer policy uses a fixed 30ms pending-audio cap.
        static let outputRealtimePendingDurationCapMs: Double = 30
        static let outputRealtimePendingDurationHardCapMs: Double = 30

        static func packetDurationMs(from advertisedPacketDuration: String?) -> Int {
            guard let advertisedPacketDuration,
                  let parsed = Int(advertisedPacketDuration)
            else {
                return defaultPacketDurationMs
            }
            return max(1, parsed)
        }

        static func isFECPayloadShardIndex(_ shardIndex: Int) -> Bool {
            shardIndex >= 0 && shardIndex < fecParityShardsPerBlock
        }

        static func isValidDynamicPayloadType(_ payloadType: Int) -> Bool {
            dynamicPayloadTypeRange.contains(payloadType)
        }

        static func plcSamplesPerChannel(
            sampleRate: Int,
            packetDurationMs: Int,
            minimumPacketSamples: Int,
            maximumPacketSamples: Int
        ) -> Int {
            let boundedPacketDurationMs = max(1, packetDurationMs)
            let rawSamples = max(
                1,
                Int((Double(sampleRate) * Double(boundedPacketDurationMs) / 1_000.0).rounded())
            )
            let sampleStep = max(1, sampleRate / 200)
            let roundedSamples = ((rawSamples + (sampleStep / 2)) / sampleStep) * sampleStep
            return max(
                minimumPacketSamples,
                min(maximumPacketSamples, max(sampleStep, roundedSamples))
            )
        }

        static func initialResyncDropPacketCount(packetDurationMs: Int) -> Int {
            let normalizedPacketDurationMs = max(1, packetDurationMs)
            return max(0, startupResyncWindowMs / normalizedPacketDurationMs)
        }

        static func recoveredPacketsPerBurstCap(availableOutputSlots: Int) -> Int {
            guard availableOutputSlots > 0 else {
                return 0
            }
            return min(availableOutputSlots, fecParityShardsPerBlock)
        }

        static func concealmentPacketsPerBurstCap(availableOutputSlots: Int) -> Int {
            guard availableOutputSlots > 0 else {
                return 0
            }
            return min(availableOutputSlots, fecDataShardsPerBlock)
        }
    }

    enum AV1 {
        static let idrFrameType: UInt8 = 2
        static let referenceInvalidatedFrameTypes: Set<UInt8> = [4, 5]

        static func isSyncFrameType(
            _ frameType: UInt8?,
            allowsReferenceInvalidatedFrame: Bool
        ) -> Bool {
            guard let frameType else {
                return false
            }
            if frameType == idrFrameType {
                return true
            }
            if allowsReferenceInvalidatedFrame {
                return referenceInvalidatedFrameTypes.contains(frameType)
            }
            return false
        }

        static func shouldDeferRecoveryRequestAfterDiscontinuity() -> Bool {
            true
        }

        static func shouldSendDeferredRecoveryRequestAfterSuccessfulFrame(
            isPendingDeferredRequest: Bool
        ) -> Bool {
            isPendingDeferredRequest
        }
    }
}
