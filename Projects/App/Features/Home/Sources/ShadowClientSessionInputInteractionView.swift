import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onSessionReactivationRequest: @MainActor () -> Void

    init(
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSessionTerminateCommand: @escaping @MainActor () -> Void = {},
        onSessionReactivationRequest: @escaping @MainActor () -> Void = {}
    ) {
        self.onInputEvent = onInputEvent
        self.onSessionTerminateCommand = onSessionTerminateCommand
        self.onSessionReactivationRequest = onSessionReactivationRequest
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand,
            onSessionReactivationRequest: onSessionReactivationRequest
        )
    }
}
