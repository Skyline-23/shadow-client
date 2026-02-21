#if os(macOS)
import AppKit
import CoreGraphics
import os
import SwiftUI

struct ShadowClientMacOSSessionInputCaptureView: NSViewRepresentable {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionInteraction: @MainActor () -> Void
    let onSessionOverlayToggleCommand: @MainActor () -> Void

    func makeNSView(context: Context) -> ShadowClientMacOSInputCaptureNSView {
        let view = ShadowClientMacOSInputCaptureNSView()
        view.onInputEvent = onInputEvent
        view.onSessionInteraction = onSessionInteraction
        view.onSessionOverlayToggleCommand = onSessionOverlayToggleCommand
        return view
    }

    func updateNSView(_ nsView: ShadowClientMacOSInputCaptureNSView, context: Context) {
        nsView.onInputEvent = onInputEvent
        nsView.onSessionInteraction = onSessionInteraction
        nsView.onSessionOverlayToggleCommand = onSessionOverlayToggleCommand
        nsView.requestInputFocusIfNeeded()
    }
}

@MainActor
final class ShadowClientMacOSInputCaptureNSView: NSView {
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?
    var onSessionInteraction: (@MainActor () -> Void)?
    var onSessionOverlayToggleCommand: (@MainActor () -> Void)?

    private var trackingAreaToken: NSTrackingArea?
    private var activeModifierFlags: NSEvent.ModifierFlags = []
    private weak var observedWindow: NSWindow?
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "InputCapture")
    private var loggedInputKinds = Set<String>()
    private var loggedFocusFailure = false
    private var isPointerCaptureActive = false
    private var isCursorHidden = false
    private var isMouseCursorAssociationDisabled = false
    private var dropNextPointerDelta = false
    private var locallyCapturedKeyCodes = Set<UInt16>()

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if observedWindow != newWindow {
            NotificationCenter.default.removeObserver(self)
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            observedWindow = nil
            deactivatePointerCaptureIfNeeded()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else {
            return
        }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey(_:)),
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidChangeScreen(_:)),
            name: NSWindow.didChangeScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidEnterFullScreen(_:)),
            name: NSWindow.didEnterFullScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidExitFullScreen(_:)),
            name: NSWindow.didExitFullScreenNotification,
            object: window
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive(_:)),
            name: NSApplication.willResignActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceDidChange(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification,
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
        if handleLocalSessionOverlayToggleShortcutIfNeeded(event) {
            return
        }
        onSessionInteraction?()
        emit(.keyDown(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    override func keyUp(with event: NSEvent) {
        if locallyCapturedKeyCodes.remove(event.keyCode) != nil {
            return
        }
        onSessionInteraction?()
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
        if locallyCapturedKeyCodes.isEmpty {
            onSessionInteraction?()
        }

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
        onSessionInteraction?()
        emit(.pointerButton(button: .left, isPressed: true))
    }

    override func mouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        onSessionInteraction?()
        emit(.pointerButton(button: .left, isPressed: false))
    }

    override func rightMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded()
        emitPointerMove(from: event)
        onSessionInteraction?()
        emit(.pointerButton(button: .right, isPressed: true))
    }

    override func rightMouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        onSessionInteraction?()
        emit(.pointerButton(button: .right, isPressed: false))
    }

    override func otherMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded()
        emitPointerMove(from: event)
        onSessionInteraction?()
        let button = event.buttonNumber == 2 ? ShadowClientRemoteMouseButton.middle : .other(Int(event.buttonNumber))
        emit(.pointerButton(button: button, isPressed: true))
    }

    override func otherMouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        onSessionInteraction?()
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
        onSessionInteraction?()
        emit(.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY))
    }

    private func emitPointerMove(from event: NSEvent) {
        if dropNextPointerDelta {
            dropNextPointerDelta = false
            return
        }

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
        onInputEvent(event)
    }

    func requestInputFocusIfNeeded(forceRecapture: Bool = false) {
        guard let window else {
            return
        }
        if !window.isKeyWindow {
            window.makeKey()
        }
        if window.firstResponder !== self {
            if !window.makeFirstResponder(self), !loggedFocusFailure {
                loggedFocusFailure = true
                logger.notice("Input capture failed to become first responder")
            } else if window.firstResponder === self {
                loggedFocusFailure = false
            }
        }

        if forceRecapture {
            deactivatePointerCaptureIfNeeded()
            recenterPointerInCaptureViewIfNeeded()
        }

        activatePointerCaptureIfNeeded()
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        requestInputFocusIfNeeded(forceRecapture: true)
    }

    @objc
    private func windowDidResignKey(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        deactivatePointerCaptureIfNeeded()
    }

    @objc
    private func applicationDidBecomeActive(_ notification: Notification) {
        _ = notification
        requestInputFocusIfNeeded(forceRecapture: true)
    }

    @objc
    private func applicationWillResignActive(_ notification: Notification) {
        _ = notification
        locallyCapturedKeyCodes.removeAll(keepingCapacity: true)
        deactivatePointerCaptureIfNeeded()
    }

    @objc
    private func windowDidChangeScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        requestInputFocusIfNeeded(forceRecapture: true)
    }

    @objc
    private func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        requestInputFocusIfNeeded(forceRecapture: true)
    }

    @objc
    private func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        requestInputFocusIfNeeded(forceRecapture: true)
    }

    @objc
    private func activeSpaceDidChange(_ notification: Notification) {
        _ = notification
        requestInputFocusIfNeeded(forceRecapture: true)
    }

    private func handleLocalSessionOverlayToggleShortcutIfNeeded(_ event: NSEvent) -> Bool {
        let requiredFlags: NSEvent.ModifierFlags = [.control, .option, .command]
        let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasRequiredFlags = requiredFlags.isSubset(of: activeFlags)
        let hasDisallowedFlags = activeFlags.contains(.shift) || activeFlags.contains(.capsLock)
        guard hasRequiredFlags, !hasDisallowedFlags else {
            return false
        }

        // Ctrl+Option+Command+M toggles local session chrome visibility.
        guard event.keyCode == 0x2E || event.charactersIgnoringModifiers?.lowercased() == "m" else {
            return false
        }

        locallyCapturedKeyCodes.insert(event.keyCode)
        onSessionOverlayToggleCommand?()
        return true
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
        case .gamepadState:
            kind = "gamepadState"
        case .gamepadArrival:
            kind = "gamepadArrival"
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

    private func activatePointerCaptureIfNeeded() {
        guard !isPointerCaptureActive,
              window?.isKeyWindow == true,
              NSApp.isActive
        else {
            return
        }

        let associationError = CGAssociateMouseAndMouseCursorPosition(0)
        if associationError == .success {
            isMouseCursorAssociationDisabled = true
        } else {
            logger.debug(
                "Input capture failed to disable mouse-cursor association: \(associationError.rawValue, privacy: .public)"
            )
        }

        if !isCursorHidden {
            NSCursor.hide()
            isCursorHidden = true
        }
        isPointerCaptureActive = true
        dropNextPointerDelta = true
    }

    private func deactivatePointerCaptureIfNeeded() {
        guard isPointerCaptureActive else {
            return
        }

        if isMouseCursorAssociationDisabled {
            _ = CGAssociateMouseAndMouseCursorPosition(1)
            isMouseCursorAssociationDisabled = false
        }
        if isCursorHidden {
            NSCursor.unhide()
            isCursorHidden = false
        }
        isPointerCaptureActive = false
    }

    private func recenterPointerInCaptureViewIfNeeded() {
        guard let window,
              window.screen != nil,
              bounds.width > 0,
              bounds.height > 0
        else {
            return
        }

        let viewCenter = NSPoint(x: bounds.midX, y: bounds.midY)
        let centerInWindow = convert(viewCenter, to: nil)
        let centerOnScreen = window.convertPoint(toScreen: centerInWindow)
        let warpResult = CGWarpMouseCursorPosition(
            CGPoint(x: centerOnScreen.x, y: centerOnScreen.y)
        )
        if warpResult != .success {
            logger.debug(
                "Input capture failed to recenter cursor: \(warpResult.rawValue, privacy: .public)"
            )
        }
    }
}
#endif
