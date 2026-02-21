#if !os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    @Binding var sessionControlsVisible: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionInteraction: @MainActor () -> Void
    let onSessionOverlayToggleCommand: @MainActor () -> Void

    var body: some View {
        let _ = onInputEvent
        let _ = onSessionOverlayToggleCommand
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sessionControlsVisible.toggle()
                }
                onSessionInteraction()
            }
    }
}
#endif
