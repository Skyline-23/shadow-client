#if os(macOS)
import AppKit
import SwiftUI

struct ShadowClientMacOSSessionInputCaptureView: NSViewRepresentable {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void

    func makeNSView(context: Context) -> ShadowClientMacOSInputCaptureNSView {
        let view = ShadowClientMacOSInputCaptureNSView()
        view.onInputEvent = onInputEvent
        return view
    }

    func updateNSView(_ nsView: ShadowClientMacOSInputCaptureNSView, context: Context) {
        nsView.onInputEvent = onInputEvent
    }
}

final class ShadowClientMacOSInputCaptureNSView: NSView {
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?

    private var trackingAreaToken: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let window {
            window.makeFirstResponder(self)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaToken {
            removeTrackingArea(trackingAreaToken)
        }

        let trackingAreaToken = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingAreaToken)
        self.trackingAreaToken = trackingAreaToken
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func keyDown(with event: NSEvent) {
        emit(.keyDown(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    override func keyUp(with event: NSEvent) {
        emit(.keyUp(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        emitPointerMove(from: event)
        emit(.pointerButton(button: .left, isPressed: true))
    }

    override func mouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        emit(.pointerButton(button: .left, isPressed: false))
    }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        emitPointerMove(from: event)
        emit(.pointerButton(button: .right, isPressed: true))
    }

    override func rightMouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        emit(.pointerButton(button: .right, isPressed: false))
    }

    override func otherMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        emitPointerMove(from: event)
        let button = event.buttonNumber == 2 ? ShadowClientRemoteMouseButton.middle : .other(Int(event.buttonNumber))
        emit(.pointerButton(button: button, isPressed: true))
    }

    override func otherMouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        let button = event.buttonNumber == 2 ? ShadowClientRemoteMouseButton.middle : .other(Int(event.buttonNumber))
        emit(.pointerButton(button: button, isPressed: false))
    }

    override func mouseMoved(with event: NSEvent) {
        emitPointerMove(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        emitPointerMove(from: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        emitPointerMove(from: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        emitPointerMove(from: event)
    }

    override func scrollWheel(with event: NSEvent) {
        emit(.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY))
    }

    private func emitPointerMove(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        emit(.pointerMoved(x: point.x, y: point.y))
    }

    private func emit(_ event: ShadowClientRemoteInputEvent) {
        guard let onInputEvent else {
            return
        }

        Task { @MainActor in
            onInputEvent(event)
        }
    }
}
#endif
