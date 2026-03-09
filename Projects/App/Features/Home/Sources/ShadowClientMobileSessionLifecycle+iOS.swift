#if os(iOS)
import SwiftUI

private struct ShadowClientMobileSessionLifecycleModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase, initial: false) { _, newPhase in
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            guard ShadowClientMobileSessionLifecyclePolicy.shouldDisconnectActiveSession(
                for: newPhase,
                isMobilePlatform: true
            ) else {
                return
            }
            remoteDesktopRuntime.clearActiveSession()
        }
    }
}

extension View {
    func shadowClientMobileSessionLifecycle(
        remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
    ) -> some View {
        modifier(
            ShadowClientMobileSessionLifecycleModifier(
                remoteDesktopRuntime: remoteDesktopRuntime
            )
        )
    }
}
#endif
