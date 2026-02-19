import CryptoKit
import Foundation

enum ShadowClientSunshineControlChannelMode: Sendable {
    case plaintext
    case encryptedV2(key: Data)

    var startAType: UInt16 {
        switch self {
        case .plaintext:
            return ShadowClientSunshineControlMessageProfile.startATypeLegacy
        case .encryptedV2:
            return ShadowClientSunshineControlMessageProfile.startATypeEncryptedV2
        }
    }

    var startBType: UInt16 {
        ShadowClientSunshineControlMessageProfile.startBType
    }

    var startAPayload: Data {
        ShadowClientSunshineControlMessageProfile.startAPayload
    }

    var startBPayload: Data {
        ShadowClientSunshineControlMessageProfile.startBPayload
    }
}

enum ShadowClientSunshineControlEncryptionError: Error {
    case invalidKeyLength(Int)
    case invalidEncryptedPacketLength
    case invalidEncryptedPayload
    case invalidEncryptedHeaderType(UInt16)
}

struct ShadowClientSunshineControlEncryptionCodec: Sendable {
    static let encryptedHeaderType: UInt16 = 0x0001
    private static let gcmTagLength = 16

    private let keyData: Data

    init(keyData: Data) throws {
        guard keyData.count == 16 else {
            throw ShadowClientSunshineControlEncryptionError.invalidKeyLength(keyData.count)
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
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPayload
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
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPacketLength
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
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPacketLength
        }

        let headerType = encryptedPacket.readUInt16LE(at: 0)
        guard headerType == Self.encryptedHeaderType else {
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedHeaderType(headerType)
        }

        let encryptedLength = Int(encryptedPacket.readUInt16LE(at: 2))
        let expectedLength = encryptedLength + 4
        guard encryptedPacket.count >= expectedLength, encryptedLength >= 4 + Self.gcmTagLength else {
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPacketLength
        }

        let sequence = encryptedPacket.readUInt32LE(at: 4)
        let tagStart = 8
        let tagEnd = tagStart + Self.gcmTagLength
        guard tagEnd <= expectedLength else {
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPacketLength
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
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPayload
        }

        let payloadLength = Int(plaintext.readUInt16LE(at: 2))
        guard plaintext.count >= 4 + payloadLength else {
            throw ShadowClientSunshineControlEncryptionError.invalidEncryptedPayload
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
