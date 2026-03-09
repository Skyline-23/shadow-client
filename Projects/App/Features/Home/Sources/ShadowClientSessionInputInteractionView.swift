import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]

    init(
        referenceVideoSize: CGSize? = nil,
        visiblePointerRegions: [CGRect] = [],
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSessionTerminateCommand: @escaping @MainActor () -> Void = {}
    ) {
        self.referenceVideoSize = referenceVideoSize
        self.visiblePointerRegions = visiblePointerRegions
        self.onInputEvent = onInputEvent
        self.onSessionTerminateCommand = onSessionTerminateCommand
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            referenceVideoSize: referenceVideoSize,
            visiblePointerRegions: visiblePointerRegions,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand
        )
    }
}
