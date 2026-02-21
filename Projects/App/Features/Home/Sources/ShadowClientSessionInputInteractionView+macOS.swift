#if os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    @Binding var sessionControlsVisible: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionInteraction: @MainActor () -> Void
    let onSessionOverlayToggleCommand: @MainActor () -> Void

    var body: some View {
        ShadowClientMacOSSessionInputCaptureView(
            onInputEvent: onInputEvent,
            onSessionInteraction: onSessionInteraction,
            onSessionOverlayToggleCommand: onSessionOverlayToggleCommand
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
#endif
