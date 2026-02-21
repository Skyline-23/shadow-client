import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    @Binding var sessionControlsVisible: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionInteraction: @MainActor () -> Void
    let onSessionOverlayToggleCommand: @MainActor () -> Void

    init(
        sessionControlsVisible: Binding<Bool>,
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSessionInteraction: @escaping @MainActor () -> Void = {},
        onSessionOverlayToggleCommand: @escaping @MainActor () -> Void = {}
    ) {
        self._sessionControlsVisible = sessionControlsVisible
        self.onInputEvent = onInputEvent
        self.onSessionInteraction = onSessionInteraction
        self.onSessionOverlayToggleCommand = onSessionOverlayToggleCommand
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            sessionControlsVisible: $sessionControlsVisible,
            onInputEvent: onInputEvent,
            onSessionInteraction: onSessionInteraction,
            onSessionOverlayToggleCommand: onSessionOverlayToggleCommand
        )
    }
}
