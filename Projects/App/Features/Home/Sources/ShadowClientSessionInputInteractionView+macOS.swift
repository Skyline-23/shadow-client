#if os(macOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]
    let captureHardwareKeyboard: Bool
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSoftwareKeyboardToggleCommand: @MainActor () -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onCopyClipboardCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void

    var body: some View {
        let _ = captureHardwareKeyboard
        let _ = onSoftwareKeyboardToggleCommand
        ShadowClientMacOSSessionInputCaptureView(
            referenceVideoSize: referenceVideoSize,
            visiblePointerRegions: visiblePointerRegions,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand,
            onCopyClipboardCommand: onCopyClipboardCommand,
            onPasteClipboardCommand: onPasteClipboardCommand
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}
#endif
