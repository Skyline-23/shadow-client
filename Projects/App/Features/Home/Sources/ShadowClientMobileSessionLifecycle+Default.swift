#if !os(iOS)
import SwiftUI

extension View {
    func shadowClientMobileSessionLifecycle(
        remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
    ) -> some View {
        self
    }
}
#endif
