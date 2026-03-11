#if os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void

    var body: some View {
        let _ = visiblePointerRegions
        ShadowClientMacOSSessionInputCaptureView(
            referenceVideoSize: referenceVideoSize,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand,
            onPasteClipboardCommand: onPasteClipboardCommand
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
#endif
