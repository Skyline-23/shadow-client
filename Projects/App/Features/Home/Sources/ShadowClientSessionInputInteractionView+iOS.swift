#if os(iOS)
import SwiftUI
import UIKit

struct ShadowClientSessionInputInteractionPlatformView: UIViewRepresentable {
    let onInputEvent: @MainActor (ShadowClientRemoteInputEvent) -> Void
    let onSessionTerminateCommand: @MainActor () -> Void

    func makeUIView(context: Context) -> ShadowClientIOSSessionInputCaptureView {
        let view = ShadowClientIOSSessionInputCaptureView()
        view.onInputEvent = onInputEvent
        view.onSessionTerminateCommand = onSessionTerminateCommand
        return view
    }

    func updateUIView(_ uiView: ShadowClientIOSSessionInputCaptureView, context: Context) {
        uiView.onInputEvent = onInputEvent
        uiView.onSessionTerminateCommand = onSessionTerminateCommand
    }
}

private final class ShadowClientIOSKeyboardCaptureTextField: UITextField {
    var onDeleteBackwardWhenEmpty: (() -> Void)?

    override func deleteBackward() {
        if (text ?? "").isEmpty {
            onDeleteBackwardWhenEmpty?()
        }
        super.deleteBackward()
    }
}

@MainActor
final class ShadowClientIOSSessionInputCaptureView: UIView, UIGestureRecognizerDelegate, UITextFieldDelegate {
    var onInputEvent: (@MainActor (ShadowClientRemoteInputEvent) -> Void)?
    var onSessionTerminateCommand: (@MainActor () -> Void)?

    private let keyboardField = ShadowClientIOSKeyboardCaptureTextField(frame: .zero)
    private var isPrimaryButtonHeld = false
    private var lastPrimaryDragLocation: CGPoint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        setupKeyboardField()
        setupGestures()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        setupKeyboardField()
        setupGestures()
    }

    deinit {
        keyboardField.delegate = nil
        keyboardField.onDeleteBackwardWhenEmpty = nil
        keyboardField.removeTarget(
            self,
            action: #selector(handleKeyboardFieldEditingChanged),
            for: .editingChanged
        )
    }

    private func setupKeyboardField() {
        keyboardField.autocapitalizationType = .none
        keyboardField.autocorrectionType = .no
        keyboardField.smartDashesType = .no
        keyboardField.smartQuotesType = .no
        keyboardField.smartInsertDeleteType = .no
        keyboardField.spellCheckingType = .no
        keyboardField.returnKeyType = .default
        keyboardField.delegate = self
        keyboardField.alpha = 0.01
        keyboardField.tintColor = .clear
        keyboardField.textColor = .clear
        keyboardField.backgroundColor = .clear
        keyboardField.text = ""
        keyboardField.onDeleteBackwardWhenEmpty = { [weak self] in
            self?.emitKeyboardCharacter("\u{08}")
        }
        addSubview(keyboardField)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        keyboardField.frame = CGRect(x: 8, y: 8, width: 1, height: 1)
    }

    private func setupGestures() {
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handlePointerPan(_:))
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)

        let singleTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handlePrimaryTap(_:))
        )
        singleTap.numberOfTouchesRequired = 1
        singleTap.numberOfTapsRequired = 1
        singleTap.delegate = self
        addGestureRecognizer(singleTap)

        let secondaryTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleSecondaryTap(_:))
        )
        secondaryTap.numberOfTouchesRequired = 2
        secondaryTap.numberOfTapsRequired = 1
        secondaryTap.delegate = self
        addGestureRecognizer(secondaryTap)

        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handlePrimaryDragPress(_:))
        )
        longPress.minimumPressDuration = 0.25
        longPress.allowableMovement = 32
        longPress.delegate = self
        addGestureRecognizer(longPress)

        let threeFingerTap = UITapGestureRecognizer(
            target: self,
            action: #selector(handleKeyboardToggleTap(_:))
        )
        threeFingerTap.numberOfTouchesRequired = 3
        threeFingerTap.numberOfTapsRequired = 1
        threeFingerTap.delegate = self
        addGestureRecognizer(threeFingerTap)

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
    private func handlePrimaryTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
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
        emit(.pointerButton(button: .right, isPressed: true))
        emit(.pointerButton(button: .right, isPressed: false))
    }

    @objc
    private func handlePrimaryDragPress(_ recognizer: UILongPressGestureRecognizer) {
        switch recognizer.state {
        case .began:
            isPrimaryButtonHeld = true
            lastPrimaryDragLocation = recognizer.location(in: self)
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
        if keyboardField.isFirstResponder {
            keyboardField.resignFirstResponder()
        } else {
            keyboardField.becomeFirstResponder()
        }
    }

    @objc
    private func handleKeyboardFieldEditingChanged() {
        keyboardField.text = ""
    }

    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String
    ) -> Bool {
        _ = textField
        if string.isEmpty, range.length > 0 {
            emitKeyboardCharacter("\u{08}")
            return false
        }
        if !string.isEmpty {
            for scalar in string.unicodeScalars {
                emitKeyboardCharacter(String(scalar))
            }
            return false
        }
        return false
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        _ = textField
        emitKeyboardCharacter("\r")
        return false
    }

    private func emitKeyboardCharacter(_ character: String) {
        emit(.keyDown(keyCode: 0, characters: character))
        emit(.keyUp(keyCode: 0, characters: character))
    }

    private func emit(_ event: ShadowClientRemoteInputEvent) {
        onInputEvent?(event)
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
#endif
