#if !os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    @Binding var sessionControlsVisible: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void

    var body: some View {
        let _ = onInputEvent
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    sessionControlsVisible.toggle()
                }
            }
    }
}
#endif
