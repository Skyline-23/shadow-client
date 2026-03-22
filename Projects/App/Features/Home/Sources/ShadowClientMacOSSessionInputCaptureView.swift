import ShadowUIFoundation
#if os(macOS)
import AppKit
import CoreGraphics
import os
import SwiftUI

enum ShadowClientMacOSPointerInputPolicy {
    static func motionEvent(
        locationInView: CGPoint,
        previousLocationInView: CGPoint?,
        containerBounds: CGRect,
        videoSize: CGSize?,
        isCaptured: Bool,
        pendingCapturedAnchor: Bool
    ) -> ShadowClientRemoteInputEvent? {
        if isCaptured && pendingCapturedAnchor {
            return absoluteMotionEvent(
                locationInView: locationInView,
                containerBounds: containerBounds,
                videoSize: videoSize
            )
        }

        if isCaptured {
            guard let previousLocationInView else {
                return nil
            }
            let deltaX = locationInView.x - previousLocationInView.x
            let deltaY = previousLocationInView.y - locationInView.y
            guard deltaX != 0 || deltaY != 0 else {
                return nil
            }
            return .pointerMoved(x: deltaX, y: deltaY)
        }

        return absoluteMotionEvent(
            locationInView: locationInView,
            containerBounds: containerBounds,
            videoSize: videoSize
        )
    }

    static func absoluteMotionEvent(
        locationInView: CGPoint,
        containerBounds: CGRect,
        videoSize: CGSize?
    ) -> ShadowClientRemoteInputEvent? {
        let topLeftLocation = CGPoint(
            x: locationInView.x,
            y: containerBounds.height - locationInView.y
        )
        guard let pointerState = ShadowClientSessionPointerGeometry.absolutePointerState(
            for: topLeftLocation,
            containerBounds: containerBounds,
            videoSize: videoSize
        ) else {
            return nil
        }
        return .pointerPosition(
            x: pointerState.x,
            y: pointerState.y,
            referenceWidth: pointerState.referenceWidth,
            referenceHeight: pointerState.referenceHeight
        )
    }

    static func shouldSyncAbsolutePointerBeforeButton(
        isCaptured: Bool,
        pendingCapturedAnchor: Bool
    ) -> Bool {
        !isCaptured || pendingCapturedAnchor
    }
}

struct ShadowClientMacOSSessionInputCaptureView: NSViewRepresentable {
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onCopyClipboardCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void

    func makeNSView(context: Context) -> ShadowClientMacOSInputCaptureNSView {
        let view = ShadowClientMacOSInputCaptureNSView()
        view.referenceVideoSize = referenceVideoSize
        view.visiblePointerRegions = visiblePointerRegions
        view.onInputEvent = onInputEvent
        view.onSessionTerminateCommand = onSessionTerminateCommand
        view.onCopyClipboardCommand = onCopyClipboardCommand
        view.onPasteClipboardCommand = onPasteClipboardCommand
        return view
    }

    func updateNSView(_ nsView: ShadowClientMacOSInputCaptureNSView, context: Context) {
        nsView.referenceVideoSize = referenceVideoSize
        nsView.visiblePointerRegions = visiblePointerRegions
        nsView.onInputEvent = onInputEvent
        nsView.onSessionTerminateCommand = onSessionTerminateCommand
        nsView.onCopyClipboardCommand = onCopyClipboardCommand
        nsView.onPasteClipboardCommand = onPasteClipboardCommand
        nsView.requestInputFocusIfNeeded()
        nsView.refreshPointerCaptureForCurrentLocation()
    }
}

@MainActor
final class ShadowClientMacOSInputCaptureNSView: NSView {
    var referenceVideoSize: CGSize?
    var visiblePointerRegions: [CGRect] = []
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?
    var onSessionTerminateCommand: (@MainActor () -> Void)?
    var onCopyClipboardCommand: (@MainActor () -> Void)?
    var onPasteClipboardCommand: (@MainActor () -> Void)?

    private var trackingAreaToken: NSTrackingArea?
    private var activeModifierFlags: NSEvent.ModifierFlags = []
    private weak var observedWindow: NSWindow?
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "InputCapture")
    private var loggedInputKinds = Set<String>()
    private var loggedFocusFailure = false
    private var isCursorHidden = false
    private var pendingCapturedPointerAnchor = false
    private var locallyHandledKeyCodes = Set<UInt16>()
    private var pendingRecaptureAfterActivation = false
    private var lastPointerLocationInView: CGPoint?

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
        if handleLocalClipboardCopyShortcutIfNeeded(event) {
            return
        }
        if handleLocalClipboardPasteShortcutIfNeeded(event) {
            return
        }
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

        if handleLocalClipboardCopyShortcutIfNeeded(event) {
            return true
        }
        if handleLocalClipboardPasteShortcutIfNeeded(event) {
            return true
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
        updatePointerCaptureLocation(from: event)
        emitPointerPositionIfNeeded(from: event)
        emit(.pointerButton(button: .left, isPressed: true))
    }

    override func mouseUp(with event: NSEvent) {
        updatePointerCaptureLocation(from: event)
        emitPointerPositionIfNeeded(from: event)
        emit(.pointerButton(button: .left, isPressed: false))
    }

    override func rightMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded(allowWindowActivation: true)
        updatePointerCaptureLocation(from: event)
        emitPointerPositionIfNeeded(from: event)
        emit(.pointerButton(button: .right, isPressed: true))
    }

    override func rightMouseUp(with event: NSEvent) {
        updatePointerCaptureLocation(from: event)
        emitPointerPositionIfNeeded(from: event)
        emit(.pointerButton(button: .right, isPressed: false))
    }

    override func otherMouseDown(with event: NSEvent) {
        requestInputFocusIfNeeded(allowWindowActivation: true)
        updatePointerCaptureLocation(from: event)
        emitPointerPositionIfNeeded(from: event)
        let button = event.buttonNumber == 2 ? ShadowClientRemoteMouseButton.middle : .other(Int(event.buttonNumber))
        emit(.pointerButton(button: button, isPressed: true))
    }

    override func otherMouseUp(with event: NSEvent) {
        updatePointerCaptureLocation(from: event)
        emitPointerPositionIfNeeded(from: event)
        let button = event.buttonNumber == 2 ? ShadowClientRemoteMouseButton.middle : .other(Int(event.buttonNumber))
        emit(.pointerButton(button: button, isPressed: false))
    }

    override func mouseMoved(with event: NSEvent) {
        emitPointerMotion(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        emitPointerMotion(from: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        emitPointerMotion(from: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        emitPointerMotion(from: event)
    }

    override func scrollWheel(with event: NSEvent) {
        emit(.scroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY))
    }

    private func emitPointerMotion(from event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        let previousLocationInView = lastPointerLocationInView
        updatePointerCaptureLocation(from: event, locationInView: locationInView)
        guard let motionEvent = ShadowClientMacOSPointerInputPolicy.motionEvent(
            locationInView: locationInView,
            previousLocationInView: previousLocationInView,
            containerBounds: bounds,
            videoSize: referenceVideoSize,
            isCaptured: isCursorHidden,
            pendingCapturedAnchor: pendingCapturedPointerAnchor
        ) else {
            return
        }
        if isCursorHidden && pendingCapturedPointerAnchor {
            pendingCapturedPointerAnchor = false
        }
        emit(motionEvent)
    }

    private func emitPointerPositionIfNeeded(from event: NSEvent) {
        guard ShadowClientMacOSPointerInputPolicy.shouldSyncAbsolutePointerBeforeButton(
            isCaptured: isCursorHidden,
            pendingCapturedAnchor: pendingCapturedPointerAnchor
        ) else {
            return
        }
        let locationInView = convert(event.locationInWindow, from: nil)
        guard let motionEvent = ShadowClientMacOSPointerInputPolicy.absoluteMotionEvent(
            locationInView: locationInView,
            containerBounds: bounds,
            videoSize: referenceVideoSize
        ) else {
            return
        }
        if isCursorHidden && pendingCapturedPointerAnchor {
            pendingCapturedPointerAnchor = false
        }
        emit(motionEvent)
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
        }

        activatePointerCaptureIfNeeded()
    }

    func refreshPointerCaptureForCurrentLocation() {
        if let location = lastPointerLocationInView {
            updatePointerCaptureVisibility(for: location)
        } else {
            updatePointerCaptureVisibility(for: nil)
        }
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

    private func updatePointerCaptureLocation(
        from event: NSEvent,
        locationInView: CGPoint? = nil
    ) {
        let locationInView = locationInView ?? convert(event.locationInWindow, from: nil)
        lastPointerLocationInView = locationInView
        updatePointerCaptureVisibility(for: locationInView)
    }

    private func updatePointerCaptureVisibility(for locationInView: CGPoint?) {
        let shouldShowCursor = locationInView.map { location in
            visiblePointerRegions.contains(where: { $0.contains(location) })
        } ?? false

        if shouldShowCursor {
            deactivatePointerCaptureIfNeeded()
        } else {
            activatePointerCaptureIfNeeded()
        }
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

    private func handleLocalClipboardPasteShortcutIfNeeded(_ event: NSEvent) -> Bool {
        let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredFlags: NSEvent.ModifierFlags = [.command]
        guard requiredFlags.isSubset(of: activeFlags),
              !activeFlags.contains(.control),
              !activeFlags.contains(.option),
              !activeFlags.contains(.shift),
              !activeFlags.contains(.capsLock),
              event.keyCode == 0x09 || event.charactersIgnoringModifiers?.lowercased() == "v"
        else {
            return false
        }

        locallyHandledKeyCodes.insert(event.keyCode)
        onPasteClipboardCommand?()
        return true
    }

    private func handleLocalClipboardCopyShortcutIfNeeded(_ event: NSEvent) -> Bool {
        let activeFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let requiredFlags: NSEvent.ModifierFlags = [.command]
        guard requiredFlags.isSubset(of: activeFlags),
              !activeFlags.contains(.control),
              !activeFlags.contains(.option),
              !activeFlags.contains(.shift),
              !activeFlags.contains(.capsLock),
              event.keyCode == 0x08 || event.charactersIgnoringModifiers?.lowercased() == "c"
        else {
            return false
        }

        locallyHandledKeyCodes.insert(event.keyCode)
        onCopyClipboardCommand?()
        return true
    }

    private func logFirstCaptureEventIfNeeded(_ event: ShadowClientRemoteInputEvent) {
        let kind: String
        switch event {
        case .keyDown:
            kind = "keyDown"
        case .keyUp:
            kind = "keyUp"
        case .text:
            kind = "text"
        case .pointerMoved:
            kind = "pointerMoved"
        case .pointerPosition:
            kind = "pointerPosition"
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
        guard !isCursorHidden,
              window?.isKeyWindow == true,
              NSApp.isActive,
              !isPointerInsideVisibleRegion
        else {
            return
        }

        NSCursor.hide()
        isCursorHidden = true
        pendingCapturedPointerAnchor = true
    }

    private func deactivatePointerCaptureIfNeeded() {
        guard isCursorHidden else {
            return
        }

        NSCursor.unhide()
        isCursorHidden = false
        pendingCapturedPointerAnchor = false
    }

    private var isPointerInsideVisibleRegion: Bool {
        guard let location = lastPointerLocationInView else {
            return false
        }
        return visiblePointerRegions.contains(where: { $0.contains(location) })
    }
}
#endif
