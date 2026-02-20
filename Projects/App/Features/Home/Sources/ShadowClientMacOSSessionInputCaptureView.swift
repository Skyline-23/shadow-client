#if os(macOS)
import AppKit
import os
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
        nsView.requestInputFocusIfNeeded()
    }
}

final class ShadowClientMacOSInputCaptureNSView: NSView {
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?

    private var trackingAreaToken: NSTrackingArea?
    private var activeModifierFlags: NSEvent.ModifierFlags = []
    private weak var observedWindow: NSWindow?
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "InputCapture")
    private var loggedInputKinds = Set<String>()
    private var loggedFocusFailure = false

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if observedWindow != newWindow {
            NotificationCenter.default.removeObserver(self)
            observedWindow = nil
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }
        window.acceptsMouseMovedEvents = true
        observedWindow = window
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive(_:)),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        activeModifierFlags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        requestInputFocusIfNeeded()
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

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        requestInputFocusIfNeeded()
        emit(.keyDown(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard let modifier = modifierMapping(for: event.keyCode) else {
            activeModifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            return
        }

        let nextFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let wasPressed = activeModifierFlags.contains(modifier.flag)
        let isPressed = nextFlags.contains(modifier.flag)
        activeModifierFlags = nextFlags

        guard wasPressed != isPressed else {
            return
        }

        if isPressed {
            emit(.keyDown(keyCode: modifier.keyCode, characters: nil))
        } else {
            emit(.keyUp(keyCode: modifier.keyCode, characters: nil))
        }
    }

    override func mouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded()
        emitPointerMove(from: event)
        emit(.pointerButton(button: .left, isPressed: true))
    }

    override func mouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        emit(.pointerButton(button: .left, isPressed: false))
    }

    override func rightMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded()
        emitPointerMove(from: event)
        emit(.pointerButton(button: .right, isPressed: true))
    }

    override func rightMouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        emit(.pointerButton(button: .right, isPressed: false))
    }

    override func otherMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded()
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
        let deltaX = event.deltaX
        let deltaY = -event.deltaY
        guard deltaX != 0 || deltaY != 0 else {
            return
        }
        emit(.pointerMoved(x: deltaX, y: deltaY))
    }

    private func emit(_ event: ShadowClientRemoteInputEvent) {
        guard let onInputEvent else {
            return
        }

        logFirstCaptureEventIfNeeded(event)
        Task { @MainActor in
            onInputEvent(event)
        }
    }

    func requestInputFocusIfNeeded() {
        guard let window else {
            return
        }
        if !window.isKeyWindow {
            window.makeKey()
        }
        guard window.firstResponder !== self else {
            return
        }
        if !window.makeFirstResponder(self), !loggedFocusFailure {
            loggedFocusFailure = true
            logger.notice("Input capture failed to become first responder")
        }
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        requestInputFocusIfNeeded()
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        _ = notification
        requestInputFocusIfNeeded()
    }

    private func logFirstCaptureEventIfNeeded(_ event: ShadowClientRemoteInputEvent) {
        let kind: String
        switch event {
        case .keyDown:
            kind = "keyDown"
        case .keyUp:
            kind = "keyUp"
        case .pointerMoved:
            kind = "pointerMoved"
        case .pointerButton:
            kind = "pointerButton"
        case .scroll:
            kind = "scroll"
        }

        guard loggedInputKinds.insert(kind).inserted else {
            return
        }
        logger.notice("Input capture emitting \(kind, privacy: .public)")
    }

    private func modifierMapping(
        for keyCode: UInt16
    ) -> (flag: NSEvent.ModifierFlags, keyCode: UInt16)? {
        switch keyCode {
        case 0x37, 0x36: // Left/Right Command
            return (.command, keyCode)
        case 0x38, 0x3C: // Left/Right Shift
            return (.shift, keyCode)
        case 0x3B, 0x3E: // Left/Right Control
            return (.control, keyCode)
        case 0x3A, 0x3D: // Left/Right Option
            return (.option, keyCode)
        case 0x39: // Caps Lock
            return (.capsLock, keyCode)
        default:
            return nil
        }
    }
}
#endif
