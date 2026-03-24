import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Native GameStream control client rejects experimental ProRes launch before network setup")
func nativeGameStreamControlClientRejectsExperimentalProResLaunchBeforeNetworkSetup() async {
    let suiteName = "ShadowClientGameStreamControlClientTests.prores.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    let controlClient = NativeGameStreamControlClient(
        identityStore: ShadowClientPairingIdentityStore(defaultsSuiteName: suiteName),
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore(defaultsSuiteName: suiteName)
    )

    do {
        _ = try await controlClient.launch(
            host: "stream-host.example.invalid",
            httpsPort: 47_984,
            appID: 881_448_767,
            currentGameID: 0,
            settings: .init(
                width: 1_920,
                height: 1_080,
                fps: 60,
                bitrateKbps: 20_000,
                preferredCodec: .prores,
                enableHDR: false,
                enableSurroundAudio: false,
                lowLatencyMode: false
            )
        )
        Issue.record("Expected experimental ProRes launch to be rejected")
    } catch let error as ShadowClientGameStreamError {
        #expect(
            error == .requestFailed(
                "ProRes is experimental in shadow and requires a custom host codec lane. Stock Sunshine/GameStream hosts are not supported yet."
            )
        )
        #expect(defaults.string(forKey: ShadowClientPairingIdentityDefaultsKeys.uniqueID) == nil)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
