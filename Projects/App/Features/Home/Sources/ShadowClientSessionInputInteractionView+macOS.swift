#if os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onSessionReactivationRequest: @MainActor () -> Void

    var body: some View {
        ShadowClientMacOSSessionInputCaptureView(
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand,
            onSessionReactivationRequest: onSessionReactivationRequest
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
#endif
