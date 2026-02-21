#if !os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void

    var body: some View {
        let _ = onInputEvent
        let _ = onSessionTerminateCommand
        Color.clear
    }
}
#endif
