import SwiftUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Mobile session lifecycle disconnects active session on background only")
func mobileSessionLifecycleDisconnectsOnlyOnBackground() {
    #expect(
        ShadowClientMobileSessionLifecyclePolicy.shouldDisconnectActiveSession(
            for: .background,
            isMobilePlatform: true
        )
    )
    #expect(
        !ShadowClientMobileSessionLifecyclePolicy.shouldDisconnectActiveSession(
            for: .active,
            isMobilePlatform: true
        )
    )
    #expect(
        !ShadowClientMobileSessionLifecyclePolicy.shouldDisconnectActiveSession(
            for: .inactive,
            isMobilePlatform: true
        )
    )
    #expect(
        !ShadowClientMobileSessionLifecyclePolicy.shouldDisconnectActiveSession(
            for: .background,
            isMobilePlatform: false
        )
    )
}
