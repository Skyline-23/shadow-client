#if os(iOS)
import SwiftUI
import UIKit

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
            let application = UIApplication.shared
            var backgroundTaskID = UIBackgroundTaskIdentifier.invalid
            backgroundTaskID = application.beginBackgroundTask(withName: "shadow-client-disconnect-stream") {
                if backgroundTaskID != .invalid {
                    application.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
            Task { @MainActor in
                await remoteDesktopRuntime.suspendActiveSessionForAppLifecycle()
                if backgroundTaskID != .invalid {
                    application.endBackgroundTask(backgroundTaskID)
                    backgroundTaskID = .invalid
                }
            }
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
