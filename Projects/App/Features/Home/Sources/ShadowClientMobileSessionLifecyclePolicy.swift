import SwiftUI

enum ShadowClientMobileSessionLifecyclePolicy {
    static func shouldDisconnectActiveSession(
        for scenePhase: ScenePhase,
        isMobilePlatform: Bool
    ) -> Bool {
        isMobilePlatform && scenePhase == .background
    }
}
