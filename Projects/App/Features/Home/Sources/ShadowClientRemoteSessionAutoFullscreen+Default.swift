#if !os(macOS)
import SwiftUI

struct ShadowClientRemoteSessionAutoFullscreenModifier: ViewModifier {
    let isSessionActive: Bool

    func body(content: Content) -> some View {
        let _ = isSessionActive
        return content
    }
}
#endif
