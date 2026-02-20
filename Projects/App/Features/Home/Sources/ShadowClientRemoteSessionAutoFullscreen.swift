import SwiftUI

extension View {
    func shadowClientRemoteSessionAutoFullscreen(
        isSessionActive: Bool
    ) -> some View {
        modifier(
            ShadowClientRemoteSessionAutoFullscreenModifier(
                isSessionActive: isSessionActive
            )
        )
    }
}
