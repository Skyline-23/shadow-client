#if os(tvOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let referenceVideoSizeProvider: @MainActor () -> CGSize?
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void

    var body: some View {
        let _ = referenceVideoSizeProvider
        let _ = onInputEvent
        let _ = onSessionTerminateCommand
        Color.clear
    }
}
#endif
