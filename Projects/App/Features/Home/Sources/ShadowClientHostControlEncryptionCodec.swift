import CryptoKit
import Foundation

enum ShadowClientHostControlChannelMode: Sendable {
    case plaintext
    case encryptedV2(key: Data)

    var startAType: UInt16 {
        switch self {
        case .plaintext:
            return ShadowClientHostControlMessageProfile.startATypeV1
        case .encryptedV2:
            return ShadowClientHostControlMessageProfile.startATypeEncryptedV2
        }
    }

    var startBType: UInt16 {
        ShadowClientHostControlMessageProfile.startBType
    }

    var startAPayload: Data {
        ShadowClientHostControlMessageProfile.startAPayload
    }

    var startBPayload: Data {
        ShadowClientHostControlMessageProfile.startBPayload
    }

    private static let plaintextIDRFallbackFrameWindow: UInt32 = 0x20

    var recoveryRequestChannelID: UInt8 {
        ShadowClientHostControlMessageProfile.urgentChannelID
    }

    func makeIDRRequest(
        lastSeenFrameIndex: UInt32?
    ) -> (type: UInt16, payload: Data, channelID: UInt8) {
        switch self {
        case .plaintext:
            let lastFrame = lastSeenFrameIndex ?? 0
            let firstFrame = lastFrame > Self.plaintextIDRFallbackFrameWindow ?
                lastFrame - Self.plaintextIDRFallbackFrameWindow :
                0
            return (
                ShadowClientHostControlMessageProfile.invalidateReferenceFramesType,
                ShadowClientHostControlMessageProfile.invalidateReferenceFramesPayload(
                    firstFrame: firstFrame,
                    lastFrame: lastFrame
                ),
                recoveryRequestChannelID
            )
        case .encryptedV2:
            return (
                ShadowClientHostControlMessageProfile.startATypeEncryptedV2,
                ShadowClientHostControlMessageProfile.startAPayload,
                recoveryRequestChannelID
            )
        }
    }

    func makeReferenceFrameInvalidationRequest(
        startFrameIndex: UInt32,
        endFrameIndex: UInt32
    ) -> (type: UInt16, payload: Data, channelID: UInt8) {
        (
            ShadowClientHostControlMessageProfile.invalidateReferenceFramesType,
            ShadowClientHostControlMessageProfile.invalidateReferenceFramesPayload(
                firstFrame: min(startFrameIndex, endFrameIndex),
                lastFrame: max(startFrameIndex, endFrameIndex)
            ),
            recoveryRequestChannelID
        )
    }
}

enum ShadowClientHostControlEncryptionError: Error {
    case invalidKeyLength(Int)
    case invalidEncryptedPacketLength
    case invalidEncryptedPayload
    case invalidEncryptedHeaderType(UInt16)
}

struct ShadowClientHostControlEncryptionCodec: Sendable {
    static let encryptedHeaderType: UInt16 = 0x0001
    private static let gcmTagLength = 16

    private let keyData: Data

    init(keyData: Data) throws {
        guard keyData.count == 16 else {
            throw ShadowClientHostControlEncryptionError.invalidKeyLength(keyData.count)
        }
        self.keyData = keyData
    }

    func encryptControlMessage(
        type: UInt16,
        payload: Data,
        sequence: UInt32,
        sourceByte10: UInt8 = 0x43
    ) throws -> Data {
        guard let payloadLength = UInt16(exactly: payload.count) else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPayload
        }
        let plaintext = makeV2ControlMessage(
            type: type,
            payload: payload,
            payloadLength: payloadLength
        )
        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: makeNonce(sequence: sequence, sourceByte10: sourceByte10))
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        let length = 4 + Self.gcmTagLength + sealed.ciphertext.count
        guard let encodedLength = UInt16(exactly: length) else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPacketLength
        }

        var packet = Data()
        packet.reserveCapacity(4 + length)
        packet.appendUInt16LE(Self.encryptedHeaderType)
        packet.appendUInt16LE(encodedLength)
        packet.appendUInt32LE(sequence)
        packet.append(sealed.tag)
        packet.append(sealed.ciphertext)
        return packet
    }

    func decryptControlMessageToV1(_ encryptedPacket: Data) throws -> Data {
        guard encryptedPacket.count >= 4 else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPacketLength
        }

        let headerType = encryptedPacket.readUInt16LE(at: 0)
        guard headerType == Self.encryptedHeaderType else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedHeaderType(headerType)
        }

        let encryptedLength = Int(encryptedPacket.readUInt16LE(at: 2))
        let expectedLength = encryptedLength + 4
        guard encryptedPacket.count >= expectedLength, encryptedLength >= 4 + Self.gcmTagLength else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPacketLength
        }

        let sequence = encryptedPacket.readUInt32LE(at: 4)
        let tagStart = 8
        let tagEnd = tagStart + Self.gcmTagLength
        guard tagEnd <= expectedLength else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPacketLength
        }

        let ciphertext = Data(encryptedPacket[tagEnd ..< expectedLength])
        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: makeNonce(sequence: sequence, sourceByte10: 0x48))
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: Data(encryptedPacket[tagStart ..< tagEnd])
        )
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        guard plaintext.count >= 4 else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPayload
        }

        let payloadLength = Int(plaintext.readUInt16LE(at: 2))
        guard plaintext.count >= 4 + payloadLength else {
            throw ShadowClientHostControlEncryptionError.invalidEncryptedPayload
        }

        var v1Payload = Data()
        v1Payload.reserveCapacity(2 + payloadLength)
        v1Payload.append(plaintext[0 ..< 2]) // V1 header keeps only type
        v1Payload.append(plaintext[4 ..< (4 + payloadLength)])
        return v1Payload
    }

    private func makeV2ControlMessage(
        type: UInt16,
        payload: Data,
        payloadLength: UInt16
    ) -> Data {
        var plaintext = Data()
        plaintext.reserveCapacity(4 + payload.count)
        plaintext.appendUInt16LE(type)
        plaintext.appendUInt16LE(payloadLength)
        plaintext.append(payload)
        return plaintext
    }

    private func makeNonce(
        sequence: UInt32,
        sourceByte10: UInt8
    ) -> Data {
        var nonce = Data(repeating: 0, count: 12)
        nonce[0] = UInt8(truncatingIfNeeded: sequence)
        nonce[1] = UInt8(truncatingIfNeeded: sequence >> 8)
        nonce[2] = UInt8(truncatingIfNeeded: sequence >> 16)
        nonce[3] = UInt8(truncatingIfNeeded: sequence >> 24)
        nonce[10] = sourceByte10
        nonce[11] = 0x43 // Control stream marker
        return nonce
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }

    func readUInt16LE(at offset: Int) -> UInt16 {
        let b0 = UInt16(self[offset])
        let b1 = UInt16(self[offset + 1]) << 8
        return b0 | b1
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
