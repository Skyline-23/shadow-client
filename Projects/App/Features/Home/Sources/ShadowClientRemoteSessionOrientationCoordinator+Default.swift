#if os(macOS) || os(tvOS)
import Foundation

@MainActor
enum ShadowClientRemoteSessionOrientationPlatformCoordinator {
    static func updateSessionState(isActive _: Bool) {}
}
#endif
