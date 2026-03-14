import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onCopyClipboardCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]

    init(
        referenceVideoSize: CGSize? = nil,
        visiblePointerRegions: [CGRect] = [],
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSessionTerminateCommand: @escaping @MainActor () -> Void = {},
        onCopyClipboardCommand: @escaping @MainActor () -> Void = {},
        onPasteClipboardCommand: @escaping @MainActor () -> Void = {}
    ) {
        self.referenceVideoSize = referenceVideoSize
        self.visiblePointerRegions = visiblePointerRegions
        self.onInputEvent = onInputEvent
        self.onSessionTerminateCommand = onSessionTerminateCommand
        self.onCopyClipboardCommand = onCopyClipboardCommand
        self.onPasteClipboardCommand = onPasteClipboardCommand
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            referenceVideoSize: referenceVideoSize,
            visiblePointerRegions: visiblePointerRegions,
            onInputEvent: onInputEvent,
            onSessionTerminateCommand: onSessionTerminateCommand,
            onCopyClipboardCommand: onCopyClipboardCommand,
            onPasteClipboardCommand: onPasteClipboardCommand
        )
    }
}
