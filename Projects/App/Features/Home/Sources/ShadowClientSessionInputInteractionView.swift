import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    @Binding var sessionControlsVisible: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            sessionControlsVisible: $sessionControlsVisible,
            onInputEvent: onInputEvent
        )
    }
}
