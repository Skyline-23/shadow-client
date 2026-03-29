import CryptoKit
import Foundation

enum ShadowClientRTSPEncryptionError: Error, Equatable {
    case invalidKeyLength(Int)
    case invalidCiphertextLength(Int)
    case invalidEncryptedHeader(UInt32)
}

struct ShadowClientRTSPEncryptionCodec: Sendable {
    static let encryptedMessageTypeBit: UInt32 = 0x8000_0000
    static let gcmTagLength = 16
    static let headerLength = 8 + gcmTagLength

    private let keyData: Data

    init(keyData: Data) throws {
        guard keyData.count == 16 else {
            throw ShadowClientRTSPEncryptionError.invalidKeyLength(keyData.count)
        }
        self.keyData = keyData
    }

    func encryptClientRTSPMessage(
        _ plaintext: Data,
        sequence: UInt32,
        sourceByte10: UInt8 = 0x43
    ) throws -> Data {
        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: makeNonce(sequence: sequence, sourceByte10: sourceByte10))
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        guard let ciphertextLength = UInt32(exactly: sealed.ciphertext.count) else {
            throw ShadowClientRTSPEncryptionError.invalidCiphertextLength(sealed.ciphertext.count)
        }

        var packet = Data()
        packet.reserveCapacity(Self.headerLength + sealed.ciphertext.count)
        packet.appendUInt32BE(Self.encryptedMessageTypeBit | ciphertextLength)
        packet.appendUInt32BE(sequence)
        packet.append(sealed.tag)
        packet.append(sealed.ciphertext)
        return packet
    }

    func decryptHostRTSPMessage(
        sequence: UInt32,
        tag: Data,
        ciphertext: Data
    ) throws -> Data {
        guard tag.count == Self.gcmTagLength else {
            throw ShadowClientRTSPEncryptionError.invalidCiphertextLength(ciphertext.count)
        }

        let key = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce(data: makeNonce(sequence: sequence, sourceByte10: 0x48))
        let sealedBox = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(sealedBox, using: key)
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
        nonce[11] = 0x52 // RTSP marker ('R')
        return nonce
    }
}

private extension Data {
    mutating func appendUInt32BE(_ value: UInt32) {
        var bigEndianValue = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndianValue) { append(contentsOf: $0) }
    }
}
