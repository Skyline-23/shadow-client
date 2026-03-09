import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let referenceVideoSizeProvider: @MainActor () -> CGSize?

    init(
        referenceVideoSizeProvider: @escaping @MainActor () -> CGSize? = { nil },
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSessionTerminateCommand: @escaping @MainActor () -> Void = {}
    ) {
        self.referenceVideoSizeProvider = referenceVideoSizeProvider
        self.onInputEvent = onInputEvent
        self.onSessionTerminateCommand = onSessionTerminateCommand
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            referenceVideoSizeProvider: referenceVideoSizeProvider,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand
        )
    }
}
