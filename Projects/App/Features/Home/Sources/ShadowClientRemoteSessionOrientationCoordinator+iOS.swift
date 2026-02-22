#if os(iOS)
import UIKit

@MainActor
enum ShadowClientRemoteSessionOrientationPlatformCoordinator {
    private static var previousSessionActiveState: Bool?

    static func updateSessionState(isActive: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            return
        }
        guard previousSessionActiveState != isActive else {
            return
        }
        previousSessionActiveState = isActive

        let orientationMask: UIInterfaceOrientationMask = isActive
            ? .landscape
            : .allButUpsideDown
        requestOrientationUpdate(mask: orientationMask)
    }

    private static func requestOrientationUpdate(mask: UIInterfaceOrientationMask) {
        let application = UIApplication.shared
        let scenes = application.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard !scenes.isEmpty else {
            return
        }

        for scene in scenes {
            let preferences = UIWindowScene.GeometryPreferences.iOS(
                interfaceOrientations: mask
            )
            scene.requestGeometryUpdate(preferences) { _ in }
            scene.windows.first(where: { $0.isKeyWindow })?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
#endif
