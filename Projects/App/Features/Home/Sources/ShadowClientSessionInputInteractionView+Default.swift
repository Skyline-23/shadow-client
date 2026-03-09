#if os(tvOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onSessionReactivationRequest: @MainActor () -> Void

    var body: some View {
        let _ = onInputEvent
        let _ = onSessionTerminateCommand
        let _ = onSessionReactivationRequest
        Color.clear
    }
}
#endif
