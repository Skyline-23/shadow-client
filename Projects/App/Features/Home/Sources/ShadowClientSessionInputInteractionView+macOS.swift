#if os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let referenceVideoSizeProvider: @MainActor () -> CGSize?
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void

    var body: some View {
        ShadowClientMacOSSessionInputCaptureView(
            referenceVideoSizeProvider: referenceVideoSizeProvider,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
#endif
