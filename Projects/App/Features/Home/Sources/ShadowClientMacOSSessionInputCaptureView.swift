#if os(macOS)
import AppKit
import CoreGraphics
import os
import SwiftUI

struct ShadowClientMacOSSessionInputCaptureView: NSViewRepresentable {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void

    func makeNSView(context: Context) -> ShadowClientMacOSInputCaptureNSView {
        let view = ShadowClientMacOSInputCaptureNSView()
        view.onInputEvent = onInputEvent
        view.onSessionTerminateCommand = onSessionTerminateCommand
        return view
    }

    func updateNSView(_ nsView: ShadowClientMacOSInputCaptureNSView, context: Context) {
        nsView.onInputEvent = onInputEvent
        nsView.onSessionTerminateCommand = onSessionTerminateCommand
        nsView.requestInputFocusIfNeeded()
    }
}

@MainActor
final class ShadowClientMacOSInputCaptureNSView: NSView {
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?
    var onSessionTerminateCommand: (@MainActor () -> Void)?

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
    private var locallyHandledKeyCodes = Set<UInt16>()
    private var pendingRecaptureAfterActivation = false

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
        if handleLocalSessionTerminateShortcutIfNeeded(event) {
            return
        }
        emit(.keyDown(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    override func keyUp(with event: NSEvent) {
        if locallyHandledKeyCodes.remove(event.keyCode) != nil {
            return
        }
        emit(.keyUp(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers))
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }

        if handleLocalSessionTerminateShortcutIfNeeded(event) {
            return true
        }

        requestInputFocusIfNeeded(allowWindowActivation: true)
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
        requestInputFocusIfNeeded(allowWindowActivation: true)
        emitPointerMove(from: event)
        emit(.pointerButton(button: .left, isPressed: true))
    }

    override func mouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        emit(.pointerButton(button: .left, isPressed: false))
    }

    override func rightMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded(allowWindowActivation: true)
        emitPointerMove(from: event)
        emit(.pointerButton(button: .right, isPressed: true))
    }

    override func rightMouseUp(with event: NSEvent) {
        emitPointerMove(from: event)
        emit(.pointerButton(button: .right, isPressed: false))
    }

    override func otherMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded(allowWindowActivation: true)
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
        if dropNextPointerDelta {
            dropNextPointerDelta = false
            return
        }

        let deltaX = event.deltaX
        let deltaY = event.deltaY
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

    func requestInputFocusIfNeeded(
        forceRecapture: Bool = false,
        allowWindowActivation: Bool = false
    ) {
        guard let window else {
            return
        }
        if !window.isKeyWindow {
            guard allowWindowActivation, NSApp.isActive else {
                if forceRecapture {
                    deactivatePointerCaptureIfNeeded()
                }
                return
            }
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
        pendingRecaptureAfterActivation = false
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
        let shouldForceWindowActivation = pendingRecaptureAfterActivation || window?.isKeyWindow != true
        pendingRecaptureAfterActivation = false
        requestInputFocusIfNeeded(
            forceRecapture: true,
            allowWindowActivation: shouldForceWindowActivation
        )
    }

    @objc
    private func applicationWillResignActive(_ notification: Notification) {
        _ = notification
        locallyHandledKeyCodes.removeAll(keepingCapacity: true)
        pendingRecaptureAfterActivation = true
        deactivatePointerCaptureIfNeeded()
    }

    @objc
    private func windowDidChangeScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        handleSessionWindowTransition(reason: "screen-change")
    }

    @objc
    private func windowDidEnterFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        handleSessionWindowTransition(reason: "enter-fullscreen")
    }

    @objc
    private func windowDidExitFullScreen(_ notification: Notification) {
        guard notification.object as? NSWindow === window else {
            return
        }
        handleSessionWindowTransition(reason: "exit-fullscreen")
    }

    @objc
    private func activeSpaceDidChange(_ notification: Notification) {
        _ = notification
        handleSessionWindowTransition(reason: "active-space-change")
    }

    private func handleSessionWindowTransition(reason: String) {
        guard let window else {
            return
        }

        // During Space/fullscreen transitions AppKit can fire window notifications
        // while the app is inactive. Defer recapture until activation to avoid
        // ending up with a dropped pointer-capture state.
        guard NSApp.isActive else {
            pendingRecaptureAfterActivation = true
            deactivatePointerCaptureIfNeeded()
            logger.notice("Input capture deferred focus recapture (\(reason, privacy: .public)) while app inactive")
            return
        }

        pendingRecaptureAfterActivation = false
        requestInputFocusIfNeeded(forceRecapture: true, allowWindowActivation: !window.isKeyWindow)
    }

    private func handleLocalSessionTerminateShortcutIfNeeded(_ event: NSEvent) -> Bool {
        let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let commandTerminateFlags: NSEvent.ModifierFlags = [.command, .option, .shift]
        let controlTerminateFlags: NSEvent.ModifierFlags = [.control, .option, .shift]

        let isCommandTerminateShortcut =
            commandTerminateFlags.isSubset(of: activeFlags) &&
            !activeFlags.contains(.control)
        let isControlTerminateShortcut =
            controlTerminateFlags.isSubset(of: activeFlags) &&
            !activeFlags.contains(.command)
        let hasDisallowedFlags = activeFlags.contains(.capsLock)
        guard !hasDisallowedFlags,
              (isCommandTerminateShortcut || isControlTerminateShortcut)
        else {
            return false
        }

        // Cmd+Option+Shift+Q or Ctrl+Option+Shift+Q ends remote session locally.
        guard event.keyCode == 0x0C || event.charactersIgnoringModifiers?.lowercased() == "q" else {
            return false
        }

        locallyHandledKeyCodes.insert(event.keyCode)
        onSessionTerminateCommand?()
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
