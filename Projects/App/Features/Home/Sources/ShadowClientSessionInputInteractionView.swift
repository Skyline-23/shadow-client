import SwiftUI

struct ShadowClientSessionInputInteractionView: View {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSoftwareKeyboardToggleCommand: @MainActor () -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onCopyClipboardCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void
    let captureHardwareKeyboard: Bool
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]

    init(
        referenceVideoSize: CGSize? = nil,
        visiblePointerRegions: [CGRect] = [],
        captureHardwareKeyboard: Bool = true,
        onInputEvent: @escaping @MainActor (ShadowClientRemoteInputEvent) -> Void,
        onSoftwareKeyboardToggleCommand: @escaping @MainActor () -> Void = {},
        onSessionTerminateCommand: @escaping @MainActor () -> Void = {},
        onCopyClipboardCommand: @escaping @MainActor () -> Void = {},
        onPasteClipboardCommand: @escaping @MainActor () -> Void = {}
    ) {
        self.referenceVideoSize = referenceVideoSize
        self.visiblePointerRegions = visiblePointerRegions
        self.captureHardwareKeyboard = captureHardwareKeyboard
        self.onInputEvent = onInputEvent
        self.onSoftwareKeyboardToggleCommand = onSoftwareKeyboardToggleCommand
        self.onSessionTerminateCommand = onSessionTerminateCommand
        self.onCopyClipboardCommand = onCopyClipboardCommand
        self.onPasteClipboardCommand = onPasteClipboardCommand
    }

    var body: some View {
        ShadowClientSessionInputInteractionPlatformView(
            referenceVideoSize: referenceVideoSize,
            visiblePointerRegions: visiblePointerRegions,
            captureHardwareKeyboard: captureHardwareKeyboard,
            onInputEvent: onInputEvent,
            onSoftwareKeyboardToggleCommand: onSoftwareKeyboardToggleCommand,
            onSessionTerminateCommand: onSessionTerminateCommand,
            onCopyClipboardCommand: onCopyClipboardCommand,
            onPasteClipboardCommand: onPasteClipboardCommand
        )
    }
}
