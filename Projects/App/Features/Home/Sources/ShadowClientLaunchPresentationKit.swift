import Foundation

enum ShadowClientLaunchPresentationKit {
    static func preferredLaunchApp(
        from apps: [ShadowClientRemoteAppDescriptor]
    ) -> ShadowClientRemoteAppDescriptor? {
        if let nonCollector = apps.first(where: { !$0.isAppCollectorGame }) {
            return nonCollector
        }
        return apps.first
    }

    static func fallbackDesktopApp(
        selectedHost: ShadowClientRemoteHostDescriptor,
        apps: [ShadowClientRemoteAppDescriptor]
    ) -> ShadowClientRemoteAppDescriptor? {
        preferredLaunchApp(from: apps) ?? {
            guard selectedHost.currentGameID > 0 else {
                return nil
            }
            return ShadowClientRemoteAppDescriptor(
                id: selectedHost.currentGameID,
                title: ShadowClientRemoteAppLabels.currentSession(selectedHost.currentGameID),
                hdrSupported: false,
                isAppCollectorGame: false
            )
        }()
    }
}
