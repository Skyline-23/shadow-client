import Foundation
import Security
import Testing
@testable import ShadowClientFeatureHome

@Test("Certificate decoder converts hex-encoded PEM certificate into DER")
func certificateDecoderConvertsHexEncodedPEM() async throws {
    let suiteName = "ShadowClientCertificateDERDecoderTests.pem.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ShadowClientPairingIdentityStore(
        provider: CertificateDecoderFailingIdentityProvider(),
        defaults: defaults
    )
    let certificatePEM = try await store.clientCertificatePEMData()
    let plainCertHex = hexString(certificatePEM)

    let decodedDER = try ShadowClientCertificateDERDecoder.decode(fromPlainCertHex: plainCertHex)
    #expect(SecCertificateCreateWithData(nil, decodedDER as CFData) != nil)
}

@Test("Certificate decoder keeps hex-encoded DER certificate as-is")
func certificateDecoderKeepsHexEncodedDER() async throws {
    let suiteName = "ShadowClientCertificateDERDecoderTests.der.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let store = ShadowClientPairingIdentityStore(
        provider: CertificateDecoderFailingIdentityProvider(),
        defaults: defaults
    )
    let certificatePEM = try await store.clientCertificatePEMData()
    let der = try parsePEMToDER(certificatePEM)

    let decodedDER = try ShadowClientCertificateDERDecoder.decode(fromPlainCertHex: hexString(der))
    #expect(decodedDER == der)
}

@Test("Certificate decoder rejects malformed plaincert payload")
func certificateDecoderRejectsMalformedPayload() {
    do {
        _ = try ShadowClientCertificateDERDecoder.decode(fromPlainCertHex: "not-a-valid-hex")
        Issue.record("Expected invalid key material error")
    } catch let error as ShadowClientGameStreamControlError {
        #expect(error == .invalidKeyMaterial)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private func parsePEMToDER(_ pemData: Data) throws -> Data {
    guard let pemText = String(data: pemData, encoding: .utf8) else {
        throw ShadowClientGameStreamControlError.invalidKeyMaterial
    }

    let body = pemText
        .components(separatedBy: .newlines)
        .filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.hasPrefix("-----BEGIN") &&
                !trimmed.hasPrefix("-----END") &&
                !trimmed.isEmpty
        }
        .joined()

    guard let der = Data(base64Encoded: body) else {
        throw ShadowClientGameStreamControlError.invalidKeyMaterial
    }
    return der
}

private func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

private struct CertificateDecoderFailingIdentityProvider: ShadowClientPairingIdentityProviding {
    func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial {
        throw ShadowClientGameStreamControlError.invalidKeyMaterial
    }
}
