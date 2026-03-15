import ShadowUIFoundation
#if os(iOS)
import SwiftUI
import UIKit

enum ShadowClientIOSIndirectPointerInputPolicy {
    static func shouldHandleDirectly(_ touchType: UITouch.TouchType) -> Bool {
        touchType == .indirectPointer
    }

    static func shouldAllowGestureRecognition(
        for touchType: UITouch.TouchType,
        recognizer: UIGestureRecognizer
    ) -> Bool {
        guard shouldHandleDirectly(touchType) else {
            return true
        }

        if recognizer is UIHoverGestureRecognizer {
            return true
        }
        if let tap = recognizer as? UITapGestureRecognizer {
            return tap.numberOfTouchesRequired == 1
        }
        return recognizer is UIPanGestureRecognizer
    }

    static func dragMoveEvent(
        translation: CGPoint,
        isPrimaryButtonHeld: Bool
    ) -> ShadowClientRemoteInputEvent? {
        guard isPrimaryButtonHeld else {
            return nil
        }
        let deltaX = Double(translation.x)
        let deltaY = Double(translation.y)
        guard deltaX != 0 || deltaY != 0 else {
            return nil
        }
        return .pointerMoved(x: deltaX, y: deltaY)
    }
}

struct ShadowClientIOSIndirectPointerTouchTransition: Equatable {
    let shouldRequestFocus: Bool
    let shouldEmitAbsolutePosition: Bool
    let buttonEvent: ShadowClientRemoteInputEvent?
    let capturesDragLocation: Bool
    let nextPrimaryButtonHeld: Bool

    static func make(
        for phase: UITouch.Phase,
        isPrimaryButtonHeld: Bool
    ) -> ShadowClientIOSIndirectPointerTouchTransition {
        switch phase {
        case .began:
            return .init(
                shouldRequestFocus: true,
                shouldEmitAbsolutePosition: true,
                buttonEvent: isPrimaryButtonHeld ? nil : .pointerButton(button: .left, isPressed: true),
                capturesDragLocation: true,
                nextPrimaryButtonHeld: true
            )
        case .ended:
            return .init(
                shouldRequestFocus: false,
                shouldEmitAbsolutePosition: true,
                buttonEvent: isPrimaryButtonHeld ? .pointerButton(button: .left, isPressed: false) : nil,
                capturesDragLocation: false,
                nextPrimaryButtonHeld: false
            )
        case .cancelled:
            return .init(
                shouldRequestFocus: false,
                shouldEmitAbsolutePosition: false,
                buttonEvent: isPrimaryButtonHeld ? .pointerButton(button: .left, isPressed: false) : nil,
                capturesDragLocation: false,
                nextPrimaryButtonHeld: false
            )
        case .moved, .regionEntered, .regionMoved, .regionExited, .stationary:
            return .init(
                shouldRequestFocus: false,
                shouldEmitAbsolutePosition: false,
                buttonEvent: nil,
                capturesDragLocation: false,
                nextPrimaryButtonHeld: isPrimaryButtonHeld
            )
        @unknown default:
            return .init(
                shouldRequestFocus: false,
                shouldEmitAbsolutePosition: false,
                buttonEvent: nil,
                capturesDragLocation: false,
                nextPrimaryButtonHeld: isPrimaryButtonHeld
            )
        }
    }
}

struct ShadowClientSessionInputInteractionPlatformView: UIViewRepresentable {
    let referenceVideoSize: CGSize?
    let visiblePointerRegions: [CGRect]
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void
    let onCopyClipboardCommand: @MainActor () -> Void
    let onPasteClipboardCommand: @MainActor () -> Void

    func makeUIView(context: Context) -> ShadowClientIOSSessionInputCaptureView {
        let view = ShadowClientIOSSessionInputCaptureView()
        view.referenceVideoSize = referenceVideoSize
        view.visiblePointerRegions = visiblePointerRegions
        view.onInputEvent = onInputEvent
        view.onSessionTerminateCommand = onSessionTerminateCommand
        view.onCopyClipboardCommand = onCopyClipboardCommand
        view.onPasteClipboardCommand = onPasteClipboardCommand
        return view
    }

    func updateUIView(_ uiView: ShadowClientIOSSessionInputCaptureView, context: Context) {
        uiView.referenceVideoSize = referenceVideoSize
        uiView.visiblePointerRegions = visiblePointerRegions
        uiView.onInputEvent = onInputEvent
        uiView.onSessionTerminateCommand = onSessionTerminateCommand
        uiView.onCopyClipboardCommand = onCopyClipboardCommand
        uiView.onPasteClipboardCommand = onPasteClipboardCommand
        uiView.requestInputFocusIfNeeded()
        uiView.invalidatePointerSuppressionRegions()
    }
}

private final class ShadowClientIOSSoftwareKeyboardInputView: UIView, UIKeyInput, UITextInputTraits {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackwardWhenEmpty: (() -> Void)?

    var keyboardType: UIKeyboardType = .default
    var keyboardAppearance: UIKeyboardAppearance = .default
    var returnKeyType: UIReturnKeyType = .default
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var smartDashesType: UITextSmartDashesType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var spellCheckingType: UITextSpellCheckingType = .no

    override var canBecomeFirstResponder: Bool { true }
    override var intrinsicContentSize: CGSize { .zero }

    var hasText: Bool { false }

    func insertText(_ text: String) {
        onInsertText?(text)
    }

    func deleteBackward() {
        onDeleteBackwardWhenEmpty?()
    }
}

@MainActor
final class ShadowClientIOSSessionInputCaptureView: UIView, UIGestureRecognizerDelegate, UIPointerInteractionDelegate {
    private enum Constants {
        static let indirectPointerScrollScale = 0.12
    }

    var referenceVideoSize: CGSize?
    var visiblePointerRegions: [CGRect] = []
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?
    var onSessionTerminateCommand: (@MainActor () -> Void)?
    var onCopyClipboardCommand: (@MainActor () -> Void)?
    var onPasteClipboardCommand: (@MainActor () -> Void)?

    private let softwareKeyboardInputView = ShadowClientIOSSoftwareKeyboardInputView(frame: .zero)
    private var directPanGestureRecognizer: UIPanGestureRecognizer?
    private var indirectPointerPanGestureRecognizer: UIPanGestureRecognizer?
    private var indirectPrimaryTapGestureRecognizer: UITapGestureRecognizer?
    private var indirectSecondaryTapGestureRecognizer: UITapGestureRecognizer?
    private var pointerInteractionRef: UIPointerInteraction?
    private var isPrimaryButtonHeld = false
    private var lastPrimaryDragLocation: CGPoint?
    private var keyboardCaptureRequested = false
    private var locallyHandledKeyCodes = Set<UInt16>()

    override var canBecomeFirstResponder: Bool { true }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        setupSoftwareKeyboardInputView()
        setupPointerInteractionIfNeeded()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        setupSoftwareKeyboardInputView()
        setupPointerInteractionIfNeeded()
        setupGestures()
    }

    private func setupSoftwareKeyboardInputView() {
        softwareKeyboardInputView.alpha = 0.01
        softwareKeyboardInputView.backgroundColor = .clear
        softwareKeyboardInputView.onInsertText = { [weak self] text in
            self?.emitSoftwareKeyboardText(text)
        }
        softwareKeyboardInputView.onDeleteBackwardWhenEmpty = { [weak self] in
            self?.emitSoftwareKeyboardText("\u{08}")
        }
        addSubview(softwareKeyboardInputView)
    }

    private func setupPointerInteractionIfNeeded() {
        let interaction = UIPointerInteraction(delegate: self)
        addInteraction(interaction)
        pointerInteractionRef = interaction
    }

    func invalidatePointerSuppressionRegions() {
        pointerInteractionRef?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        softwareKeyboardInputView.frame = CGRect(x: 8, y: 8, width: 1, height: 1)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            softwareKeyboardInputView.resignFirstResponder()
            resignFirstResponder()
            return
        }
        requestInputFocusIfNeeded()
    }

    func requestInputFocusIfNeeded() {
        guard window != nil else {
            return
        }

        if keyboardCaptureRequested {
            requestSoftwareKeyboardFirstResponder()
        } else {
            requestHardwareKeyboardFirstResponder()
        }
    }

    private func requestHardwareKeyboardFirstResponder() {
        guard isFirstResponder == false else {
            return
        }
        if becomeFirstResponder() {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.keyboardCaptureRequested else {
                return
            }
            _ = self.becomeFirstResponder()
        }
    }

    private func requestSoftwareKeyboardFirstResponder() {
        guard softwareKeyboardInputView.isFirstResponder == false else {
            return
        }
        if softwareKeyboardInputView.becomeFirstResponder() {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, self.keyboardCaptureRequested else {
                return
            }
            _ = self.softwareKeyboardInputView.becomeFirstResponder()
        }
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePointerPan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.delegate = self
        addGestureRecognizer(pan)
        directPanGestureRecognizer = pan

        let indirectPan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleIndirectPointerPan(_:))
        )
        indirectPan.minimumNumberOfTouches = 1
        indirectPan.maximumNumberOfTouches = 1
        indirectPan.allowedScrollTypesMask = .all
        indirectPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        indirectPan.delegate = self
        addGestureRecognizer(indirectPan)
        indirectPointerPanGestureRecognizer = indirectPan

        let singleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handlePrimaryTap(_:))
        )
        singleTap.numberOfTouchesRequired = 1
        singleTap.numberOfTapsRequired = 1
        singleTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        singleTap.delegate = self
        addGestureRecognizer(singleTap)

        let indirectPrimaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handlePrimaryTap(_:))
        )
        indirectPrimaryTap.numberOfTouchesRequired = 1
        indirectPrimaryTap.numberOfTapsRequired = 1
        indirectPrimaryTap.buttonMaskRequired = .primary
        indirectPrimaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        indirectPrimaryTap.delegate = self
        addGestureRecognizer(indirectPrimaryTap)
        indirectPrimaryTapGestureRecognizer = indirectPrimaryTap

        let secondaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSecondaryTap(_:))
        )
        secondaryTap.numberOfTouchesRequired = 2
        secondaryTap.numberOfTapsRequired = 1
        secondaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        secondaryTap.delegate = self
        addGestureRecognizer(secondaryTap)

        let indirectSecondaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSecondaryTap(_:))
        )
        indirectSecondaryTap.numberOfTouchesRequired = 1
        indirectSecondaryTap.numberOfTapsRequired = 1
        indirectSecondaryTap.buttonMaskRequired = .secondary
        indirectSecondaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        indirectSecondaryTap.delegate = self
        addGestureRecognizer(indirectSecondaryTap)
        indirectSecondaryTapGestureRecognizer = indirectSecondaryTap

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handlePrimaryDragPress(_:))
        )
        longPress.minimumPressDuration = 0.25
        longPress.allowableMovement = 32
        longPress.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        longPress.delegate = self
        addGestureRecognizer(longPress)

        let threeFingerTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleKeyboardToggleTap(_:))
        )
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.numberOfTapsRequired = 1
        threeFingerTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        threeFingerTap.delegate = self
        addGestureRecognizer(threeFingerTap)

        let hover = UIHoverGestureRecognizer(
            target: self,
            action: #selector(handlePointerHover(_:))
        )
        hover.delegate = self
        addGestureRecognizer(hover)

        singleTap.require(toFail: longPress)
        singleTap.require(toFail: threeFingerTap)
    }

    @objc
    private func handlePointerPan(_ recognizer: UIPanGestureRecognizer) {
        if isPrimaryButtonHeld {
            return
        }
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)
        let deltaX = Double(translation.x)
        let deltaY = Double(translation.y)
        guard deltaX != 0 || deltaY != 0 else {
            return
        }
        emit(.pointerMoved(x: deltaX, y: deltaY))
    }

    @objc
    private func handleIndirectPointerPan(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        let translation = recognizer.translation(in: self)
        recognizer.setTranslation(.zero, in: self)

        if recognizer.buttonMask.contains(.primary) || isPrimaryButtonHeld {
            switch recognizer.state {
            case .began:
                requestInputFocusIfNeeded()
                if !isPrimaryButtonHeld {
                    isPrimaryButtonHeld = true
                    emitAbsolutePointerPosition(at: location)
                    emit(.pointerButton(button: .left, isPressed: true))
                }
            case .changed:
                if !isPrimaryButtonHeld {
                    isPrimaryButtonHeld = true
                    emit(.pointerButton(button: .left, isPressed: true))
                }
                if let dragMoveEvent = ShadowClientIOSIndirectPointerInputPolicy.dragMoveEvent(
                    translation: translation,
                    isPrimaryButtonHeld: isPrimaryButtonHeld
                ) {
                    emit(dragMoveEvent)
                }
            case .ended, .cancelled, .failed:
                emitAbsolutePointerPosition(at: location)
                if isPrimaryButtonHeld {
                    isPrimaryButtonHeld = false
                    emit(.pointerButton(button: .left, isPressed: false))
                }
            default:
                break
            }
            return
        }

        let deltaX = Double(translation.x)
        let deltaY = Double(translation.y)
        guard deltaX != 0 || deltaY != 0 else {
            return
        }
        emit(
            .scroll(
                deltaX: deltaX * Constants.indirectPointerScrollScale,
                deltaY: deltaY * Constants.indirectPointerScrollScale
            )
        )
    }

    @objc
    private func handlePrimaryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        emitAbsolutePointerPosition(at: recognizer.location(in: self))
        if recognizer === indirectPrimaryTapGestureRecognizer {
            if isPrimaryButtonHeld {
                isPrimaryButtonHeld = false
                emit(.pointerButton(button: .left, isPressed: false))
            } else {
                emit(.pointerButton(button: .left, isPressed: true))
                emit(.pointerButton(button: .left, isPressed: false))
            }
            return
        }
        emit(.pointerButton(button: .left, isPressed: true))
        emit(.pointerButton(button: .left, isPressed: false))
    }

    @objc
    private func handleSecondaryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        emitAbsolutePointerPosition(at: recognizer.location(in: self))
        emit(.pointerButton(button: .right, isPressed: true))
        emit(.pointerButton(button: .right, isPressed: false))
    }

    @objc
    private func handlePrimaryDragPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isPrimaryButtonHeld = true
            lastPrimaryDragLocation = recognizer.location(in: self)
            emitAbsolutePointerPosition(at: recognizer.location(in: self))
            emit(.pointerButton(button: .left, isPressed: true))
        case .changed:
            let location = recognizer.location(in: self)
            if let previousLocation = lastPrimaryDragLocation {
                let deltaX = Double(location.x - previousLocation.x)
                let deltaY = Double(location.y - previousLocation.y)
                if deltaX != 0 || deltaY != 0 {
                    emit(.pointerMoved(x: deltaX, y: deltaY))
                }
            }
            lastPrimaryDragLocation = location
        case .ended, .cancelled, .failed:
            if isPrimaryButtonHeld {
                isPrimaryButtonHeld = false
                emit(.pointerButton(button: .left, isPressed: false))
            }
            lastPrimaryDragLocation = nil
        default:
            break
        }
    }

    @objc
    private func handleKeyboardToggleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }
        keyboardCaptureRequested.toggle()
        requestInputFocusIfNeeded()
    }

    @objc
    private func handlePointerHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            emitAbsolutePointerPosition(at: recognizer.location(in: self))
        default:
            break
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remainingTouches = handleIndirectPointerTouches(
            touches,
            phase: .began
        )
        if !remainingTouches.isEmpty {
            super.touchesBegan(remainingTouches, with: event)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remainingTouches = handleIndirectPointerTouches(
            touches,
            phase: .moved
        )
        if !remainingTouches.isEmpty {
            super.touchesMoved(remainingTouches, with: event)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remainingTouches = handleIndirectPointerTouches(
            touches,
            phase: .ended
        )
        if !remainingTouches.isEmpty {
            super.touchesEnded(remainingTouches, with: event)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        let remainingTouches = handleIndirectPointerTouches(
            touches,
            phase: .cancelled
        )
        if !remainingTouches.isEmpty {
            super.touchesCancelled(remainingTouches, with: event)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = handleKeyboardPresses(presses, isPressed: true)
        if !unhandledPresses.isEmpty {
            super.pressesBegan(unhandledPresses, with: event)
        }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = handleKeyboardPresses(presses, isPressed: false)
        if !unhandledPresses.isEmpty {
            super.pressesEnded(unhandledPresses, with: event)
        }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandledPresses = handleKeyboardPresses(presses, isPressed: false)
        if !unhandledPresses.isEmpty {
            super.pressesCancelled(unhandledPresses, with: event)
        }
    }

    private func handleKeyboardPresses(
        _ presses: Set<UIPress>,
        isPressed: Bool
    ) -> Set<UIPress> {
        var unhandledPresses = Set<UIPress>()

        for press in presses {
            guard let key = press.key
            else {
                unhandledPresses.insert(press)
                continue
            }

            if isPressed, handleLocalSessionTerminateShortcutIfNeeded(key) {
                locallyHandledKeyCodes.insert(UInt16(key.keyCode.rawValue))
                continue
            }

            if isPressed, handleLocalClipboardCopyShortcutIfNeeded(key) {
                locallyHandledKeyCodes.insert(UInt16(key.keyCode.rawValue))
                continue
            }

            if isPressed, handleLocalClipboardPasteShortcutIfNeeded(key) {
                locallyHandledKeyCodes.insert(UInt16(key.keyCode.rawValue))
                continue
            }

            let hidUsage = UInt16(key.keyCode.rawValue)
            if !isPressed, locallyHandledKeyCodes.remove(hidUsage) != nil {
                continue
            }

            guard let virtualKey = ShadowClientWindowsVirtualKeyMap.windowsVirtualKeyCode(
                keyboardHIDUsage: key.keyCode,
                characters: key.charactersIgnoringModifiers
            ) else {
                unhandledPresses.insert(press)
                continue
            }

            let translatedKeyCode = ShadowClientRemoteInputEvent.pretranslatedWindowsVirtualKey(virtualKey)
            let inputEvent: ShadowClientRemoteInputEvent = isPressed
                ? .keyDown(keyCode: translatedKeyCode, characters: key.charactersIgnoringModifiers)
                : .keyUp(keyCode: translatedKeyCode, characters: key.charactersIgnoringModifiers)
            emit(inputEvent)
        }

        return unhandledPresses
    }

    private func handleLocalSessionTerminateShortcutIfNeeded(_ key: UIKey) -> Bool {
        let activeFlags = key.modifierFlags
        let commandTerminateFlags: UIKeyModifierFlags = [.command, .alternate, .shift]
        let controlTerminateFlags: UIKeyModifierFlags = [.control, .alternate, .shift]

        let isCommandTerminateShortcut =
            commandTerminateFlags.isSubset(of: activeFlags) &&
            !activeFlags.contains(.control)
        let isControlTerminateShortcut =
            controlTerminateFlags.isSubset(of: activeFlags) &&
            !activeFlags.contains(.command)
        guard isCommandTerminateShortcut || isControlTerminateShortcut else {
            return false
        }

        let isQKey = key.keyCode == .keyboardQ || key.charactersIgnoringModifiers.lowercased() == "q"
        guard isQKey else {
            return false
        }

        onSessionTerminateCommand?()
        return true
    }

    private func handleLocalClipboardPasteShortcutIfNeeded(_ key: UIKey) -> Bool {
        let activeFlags = key.modifierFlags
        let requiredFlags: UIKeyModifierFlags = [.command]
        guard requiredFlags.isSubset(of: activeFlags),
              !activeFlags.contains(.control),
              !activeFlags.contains(.alternate),
              !activeFlags.contains(.shift),
              key.keyCode == .keyboardV || key.charactersIgnoringModifiers.lowercased() == "v"
        else {
            return false
        }

        onPasteClipboardCommand?()
        return true
    }

    private func handleLocalClipboardCopyShortcutIfNeeded(_ key: UIKey) -> Bool {
        let activeFlags = key.modifierFlags
        let requiredFlags: UIKeyModifierFlags = [.command]
        guard requiredFlags.isSubset(of: activeFlags),
              !activeFlags.contains(.control),
              !activeFlags.contains(.alternate),
              !activeFlags.contains(.shift),
              key.keyCode == .keyboardC || key.charactersIgnoringModifiers.lowercased() == "c"
        else {
            return false
        }

        onCopyClipboardCommand?()
        return true
    }

    private func emitAbsolutePointerPosition(at location: CGPoint) {
        guard let pointerState = ShadowClientSessionPointerGeometry.absolutePointerState(
            for: location,
            containerBounds: bounds,
            videoSize: referenceVideoSize
        ) else {
            return
        }

        emit(
            .pointerPosition(
                x: pointerState.x,
                y: pointerState.y,
                referenceWidth: pointerState.referenceWidth,
                referenceHeight: pointerState.referenceHeight
            )
        )
    }

    private func emitSoftwareKeyboardText(_ text: String) {
        for scalar in text.unicodeScalars {
            let character = String(scalar)
            emit(
                .keyDown(
                    keyCode: ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
                    characters: character
                )
            )
            emit(
                .keyUp(
                    keyCode: ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
                    characters: character
                )
            )
        }
    }

    private func emit(_ event: ShadowClientRemoteInputEvent) {
        onInputEvent?(event)
    }

    func pointerInteraction(
        _: UIPointerInteraction,
        regionFor request: UIPointerRegionRequest,
        defaultRegion: UIPointerRegion
    ) -> UIPointerRegion? {
        if visiblePointerRegions.contains(where: { $0.contains(request.location) }) {
            return nil
        }
        return defaultRegion
    }

    func pointerInteraction(
        _: UIPointerInteraction,
        styleFor _: UIPointerRegion
    ) -> UIPointerStyle? {
        .hidden()
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        false
    }

    func gestureRecognizer(
        _ recognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        return ShadowClientIOSIndirectPointerInputPolicy.shouldAllowGestureRecognition(
            for: touch.type,
            recognizer: recognizer
        )
    }

    private func handleIndirectPointerTouches(
        _ touches: Set<UITouch>,
        phase: UITouch.Phase
    ) -> Set<UITouch> {
        var remainingTouches = Set<UITouch>()

        for touch in touches {
            guard ShadowClientIOSIndirectPointerInputPolicy.shouldHandleDirectly(touch.type) else {
                remainingTouches.insert(touch)
                continue
            }

            let location = touch.location(in: self)
            let transition = ShadowClientIOSIndirectPointerTouchTransition.make(
                for: phase,
                isPrimaryButtonHeld: isPrimaryButtonHeld
            )

            if transition.shouldRequestFocus {
                requestInputFocusIfNeeded()
            }
            if transition.shouldEmitAbsolutePosition {
                emitAbsolutePointerPosition(at: location)
            }
            if let buttonEvent = transition.buttonEvent {
                emit(buttonEvent)
            }
            isPrimaryButtonHeld = transition.nextPrimaryButtonHeld
            if transition.capturesDragLocation {
                lastPrimaryDragLocation = location
            } else {
                lastPrimaryDragLocation = nil
            }
        }

        return remainingTouches
    }
}
#endif
