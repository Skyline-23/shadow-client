#if os(tvOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let referenceVideoSizeProvider: @MainActor () -> CGSize?
    let visiblePointerRegionsProvider: @MainActor () -> [CGRect]
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void

    var body: some View {
        let _ = referenceVideoSizeProvider
        let _ = visiblePointerRegionsProvider
        let _ = onInputEvent
        let _ = onSessionTerminateCommand
        Color.clear
    }
}
#endif
