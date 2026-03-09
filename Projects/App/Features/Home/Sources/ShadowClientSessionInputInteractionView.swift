import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let referenceVideoSizeProvider: @MainActor () -> CGSize?
    let visiblePointerRegionsProvider: @MainActor () -> [CGRect]

    init(
        referenceVideoSizeProvider: @escaping @MainActor () -> CGSize? = { nil },
        visiblePointerRegionsProvider: @escaping @MainActor () -> [CGRect] = { [] },
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSessionTerminateCommand: @escaping @MainActor () -> Void = {}
    ) {
        self.referenceVideoSizeProvider = referenceVideoSizeProvider
        self.visiblePointerRegionsProvider = visiblePointerRegionsProvider
        self.onInputEvent = onInputEvent
        self.onSessionTerminateCommand = onSessionTerminateCommand
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            referenceVideoSizeProvider: referenceVideoSizeProvider,
            visiblePointerRegionsProvider: visiblePointerRegionsProvider,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand
        )
    }
}
