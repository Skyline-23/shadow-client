#if os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    @Binding var sessionControlsVisible: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void

    var body: some View {
        ShadowClientMacOSSessionInputCaptureView(onInputEvent: onInputEvent)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
#endif
