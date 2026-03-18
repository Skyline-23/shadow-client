#if os(tvOS)
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
        let _ = referenceVideoSize
        let _ = visiblePointerRegions
        let _ = captureHardwareKeyboard
        let _ = onInputEvent
        let _ = onSoftwareKeyboardToggleCommand
        let _ = onSessionTerminateCommand
        let _ = onCopyClipboardCommand
        let _ = onPasteClipboardCommand
        Color.clear
    }
}
#endif
