import Testing
@testable import ShadowClientFeatureHome
import Foundation

@Test("Moonlight audio RS-FEC queue recovers single missing shard from one parity shard")
func moonlightAudioRSFECQueueRecoversSingleMissingShard() async {
    let queue = ShadowClientRealtimeAudioMoonlightRSFECQueue()
    let baseSequence: UInt16 = 400
    let baseTimestamp: UInt32 = 2_000
    let payloadType = 97

    let dataShards = [
        Data([0x10, 0x11, 0x12, 0x13]),
        Data([0x20, 0x21, 0x22, 0x23]),
        Data([0x30, 0x31, 0x32, 0x33]),
        Data([0x40, 0x41, 0x42, 0x43]),
    ]

    let parityShard0 = makeParityShard(dataShards: dataShards, row: 0)

    await queue.ingest(
        packetSequenceNumber: baseSequence,
        packetTimestamp: baseTimestamp,
        payloadType: payloadType,
        payload: dataShards[0],
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )
    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 1,
        packetTimestamp: baseTimestamp &+ 5,
        payloadType: payloadType,
        payload: dataShards[1],
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )
    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 3,
        packetTimestamp: baseTimestamp &+ 15,
        payloadType: payloadType,
        payload: dataShards[3],
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )

    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 4,
        packetTimestamp: baseTimestamp &+ 20,
        payloadType: 127,
        payload: makeFECShardPayload(
            shardIndex: 0,
            primaryPayloadType: payloadType,
            baseSequenceNumber: baseSequence,
            baseTimestamp: baseTimestamp,
            shardPayload: parityShard0
        ),
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )

    let recovered = await queue.takeRecoveredPayload(sequenceNumber: baseSequence &+ 2)
    #expect(recovered == dataShards[2])
}

@Test("Moonlight audio RS-FEC queue recovers two missing shards from two parity shards")
func moonlightAudioRSFECQueueRecoversTwoMissingShards() async {
    let queue = ShadowClientRealtimeAudioMoonlightRSFECQueue()
    let baseSequence: UInt16 = 600
    let baseTimestamp: UInt32 = 9_000
    let payloadType = 97

    let dataShards = [
        Data([0x01, 0x02, 0x03, 0x04, 0x05]),
        Data([0x10, 0x20, 0x30, 0x40, 0x50]),
        Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]),
        Data([0xF1, 0xF2, 0xF3, 0xF4, 0xF5]),
    ]

    let parityShard0 = makeParityShard(dataShards: dataShards, row: 0)
    let parityShard1 = makeParityShard(dataShards: dataShards, row: 1)

    await queue.ingest(
        packetSequenceNumber: baseSequence,
        packetTimestamp: baseTimestamp,
        payloadType: payloadType,
        payload: dataShards[0],
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )
    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 3,
        packetTimestamp: baseTimestamp &+ 15,
        payloadType: payloadType,
        payload: dataShards[3],
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )

    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 4,
        packetTimestamp: baseTimestamp &+ 20,
        payloadType: 127,
        payload: makeFECShardPayload(
            shardIndex: 0,
            primaryPayloadType: payloadType,
            baseSequenceNumber: baseSequence,
            baseTimestamp: baseTimestamp,
            shardPayload: parityShard0
        ),
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )
    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 5,
        packetTimestamp: baseTimestamp &+ 25,
        payloadType: 127,
        payload: makeFECShardPayload(
            shardIndex: 1,
            primaryPayloadType: payloadType,
            baseSequenceNumber: baseSequence,
            baseTimestamp: baseTimestamp,
            shardPayload: parityShard1
        ),
        expectedPrimaryPayloadType: payloadType,
        wrapperPayloadType: 127
    )

    let recoveredOne = await queue.takeRecoveredPayload(sequenceNumber: baseSequence &+ 1)
    let recoveredTwo = await queue.takeRecoveredPayload(sequenceNumber: baseSequence &+ 2)

    #expect(recoveredOne == dataShards[1])
    #expect(recoveredTwo == dataShards[2])
}

@Test("Moonlight audio RS-FEC queue ignores parity shards with mismatched primary payload type")
func moonlightAudioRSFECQueueIgnoresMismatchedPrimaryPayloadType() async {
    let queue = ShadowClientRealtimeAudioMoonlightRSFECQueue()
    let baseSequence: UInt16 = 800
    let baseTimestamp: UInt32 = 15_000

    let dataShards = [
        Data([0x01, 0x01, 0x01, 0x01]),
        Data([0x02, 0x02, 0x02, 0x02]),
        Data([0x03, 0x03, 0x03, 0x03]),
        Data([0x04, 0x04, 0x04, 0x04]),
    ]
    let parityShard0 = makeParityShard(dataShards: dataShards, row: 0)

    await queue.ingest(
        packetSequenceNumber: baseSequence,
        packetTimestamp: baseTimestamp,
        payloadType: 97,
        payload: dataShards[0],
        expectedPrimaryPayloadType: 97,
        wrapperPayloadType: 127
    )
    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 1,
        packetTimestamp: baseTimestamp &+ 5,
        payloadType: 97,
        payload: dataShards[1],
        expectedPrimaryPayloadType: 97,
        wrapperPayloadType: 127
    )
    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 3,
        packetTimestamp: baseTimestamp &+ 15,
        payloadType: 97,
        payload: dataShards[3],
        expectedPrimaryPayloadType: 97,
        wrapperPayloadType: 127
    )

    await queue.ingest(
        packetSequenceNumber: baseSequence &+ 4,
        packetTimestamp: baseTimestamp &+ 20,
        payloadType: 127,
        payload: makeFECShardPayload(
            shardIndex: 0,
            primaryPayloadType: 98,
            baseSequenceNumber: baseSequence,
            baseTimestamp: baseTimestamp,
            shardPayload: parityShard0
        ),
        expectedPrimaryPayloadType: 97,
        wrapperPayloadType: 127
    )

    let recovered = await queue.takeRecoveredPayload(sequenceNumber: baseSequence &+ 2)
    #expect(recovered == nil)
}

private let parityRows: [[UInt8]] = [
    [0x77, 0x40, 0x38, 0x0E],
    [0xC7, 0xA7, 0x0D, 0x6C],
]

private func makeParityShard(
    dataShards: [Data],
    row: Int
) -> Data {
    precondition(dataShards.count == 4)
    let shardLength = dataShards[0].count
    precondition(dataShards.allSatisfy { $0.count == shardLength })

    let coefficients = parityRows[row]
    var parity = Array(repeating: UInt8(0), count: shardLength)
    let dataBytes = dataShards.map { [UInt8]($0) }

    for byteOffset in 0 ..< shardLength {
        var value: UInt8 = 0
        for shardIndex in 0 ..< 4 {
            value ^= gfMultiply(coefficients[shardIndex], dataBytes[shardIndex][byteOffset])
        }
        parity[byteOffset] = value
    }

    return Data(parity)
}

private func makeFECShardPayload(
    shardIndex: Int,
    primaryPayloadType: Int,
    baseSequenceNumber: UInt16,
    baseTimestamp: UInt32,
    shardPayload: Data
) -> Data {
    var payload = Data()
    payload.append(UInt8(shardIndex & 0xFF))
    payload.append(UInt8(primaryPayloadType & 0x7F))
    payload.append(UInt8((baseSequenceNumber >> 8) & 0xFF))
    payload.append(UInt8(baseSequenceNumber & 0xFF))
    payload.append(UInt8((baseTimestamp >> 24) & 0xFF))
    payload.append(UInt8((baseTimestamp >> 16) & 0xFF))
    payload.append(UInt8((baseTimestamp >> 8) & 0xFF))
    payload.append(UInt8(baseTimestamp & 0xFF))
    payload.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
    payload.append(shardPayload)
    return payload
}

private func gfMultiply(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
    var a = lhs
    var b = rhs
    var result: UInt8 = 0
    while b > 0 {
        if (b & 1) != 0 {
            result ^= a
        }
        let carry = (a & 0x80) != 0
        a <<= 1
        if carry {
            a ^= 0x1D
        }
        b >>= 1
    }
    return result
}
