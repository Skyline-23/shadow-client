#if os(tvOS)
import SwiftUI

struct ShadowClientSessionInputInteractionPlatformView: View {
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onCopyClipboardCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void

    var body: some View {
        let _ = referenceVideoSize
        let _ = visiblePointerRegions
        let _ = onInputEvent
        let _ = onSessionTerminateCommand
        let _ = onCopyClipboardCommand
        let _ = onPasteClipboardCommand
        Color.clear
    }
}
#endif
