import Foundation

@MainActor
enum ShadowClientRemoteSessionOrientationCoordinator {
    static func updateSessionState(isActive: Bool) {
        ShadowClientRemoteSessionOrientationPlatformCoordinator.updateSessionState(
            isActive: isActive
        )
    }
}
