#if os(iOS) || os(tvOS)
import SwiftUI
import UIKit

extension ShadowClientPlatformTextField {
    var platformBody: some View {
        ShadowClientPlatformUIKitTextField(
            text: $text,
            placeholder: placeholder,
            isFocused: isFocused,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            submitAction: submitAction,
            textAlignment: textAlignment,
            keyboardType: keyboardType,
            submitLabel: submitLabel,
            showsDoneToolbar: showsDoneToolbar,
            textOpacity: textOpacity,
            usesMonospacedFont: usesMonospacedFont,
            fontWeight: fontWeight,
            isSecureTextEntry: isSecureTextEntry
        )
    }
}

extension ShadowClientPlatformTextView {
    var platformBody: some View {
        ShadowClientPlatformUIKitTextView(
            text: $text,
            placeholder: placeholder,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            textOpacity: textOpacity,
            usesMonospacedFont: usesMonospacedFont,
            fontWeight: fontWeight,
            showsDoneToolbar: showsDoneToolbar
        )
    }
}

private struct ShadowClientPlatformUIKitTextField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isFocused: Binding<Bool>?
    let accessibilityIdentifier: String?
    let accessibilityLabel: String?
    let submitAction: () -> Void
    let textAlignment: ShadowClientPlatformTextFieldAlignment
    let keyboardType: ShadowClientPlatformTextFieldKeyboardType
    let submitLabel: ShadowClientPlatformTextFieldSubmitLabel
    let showsDoneToolbar: Bool
    let textOpacity: Double
    let usesMonospacedFont: Bool
    let fontWeight: ShadowClientPlatformTextFieldWeight
    let isSecureTextEntry: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)
        textField.placeholder = placeholder
        textField.text = text
        textField.tintColor = .white
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.textContentType = nil
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.isSecureTextEntry = isSecureTextEntry
        textField.keyboardType = keyboardType.uiKitValue
        textField.returnKeyType = submitLabel.uiKitValue
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        if showsDoneToolbar {
            textField.inputAccessoryView = context.coordinator.makeDoneToolbar()
        }
        textField.accessibilityIdentifier = accessibilityIdentifier
        textField.accessibilityLabel = accessibilityLabel
        configureAppearance(textField)
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self

        if textField.markedTextRange == nil, textField.text != text {
            textField.text = text
        }

        configureAppearance(textField)

        guard let isFocused else {
            return
        }

        let shouldBeFirstResponder = isFocused.wrappedValue
        if shouldBeFirstResponder, !textField.isFirstResponder {
            DispatchQueue.main.async {
                guard self.isFocused?.wrappedValue == true else {
                    return
                }
                textField.becomeFirstResponder()
            }
        } else if !shouldBeFirstResponder, textField.isFirstResponder {
            DispatchQueue.main.async {
                guard self.isFocused?.wrappedValue != true else {
                    return
                }
                textField.resignFirstResponder()
            }
        }
    }

    private func configureAppearance(_ textField: UITextField) {
        textField.textAlignment = textAlignment.uiKitValue
        textField.textColor = UIColor.white.withAlphaComponent(textOpacity)
        textField.font = usesMonospacedFont
            ? UIFont.monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: fontWeight.uiKitValue
            )
            : UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: fontWeight.uiKitValue
            )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ShadowClientPlatformUIKitTextField
        weak var activeTextField: UITextField?

        init(_ parent: ShadowClientPlatformUIKitTextField) {
            self.parent = parent
        }

        func makeDoneToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(
                    barButtonSystemItem: .done,
                    target: self,
                    action: #selector(didTapDone)
                ),
            ]
            return toolbar
        }

        @objc func textDidChange(_ textField: UITextField) {
            if textField.markedTextRange != nil {
                return
            }
            let newValue = textField.text ?? ""
            if parent.text != newValue {
                parent.text = newValue
            }
        }

        @objc func didTapDone() {
            activeTextField?.resignFirstResponder()
            parent.submitAction()
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            activeTextField = textField
            if parent.isFocused?.wrappedValue != true {
                DispatchQueue.main.async {
                    self.parent.isFocused?.wrappedValue = true
                }
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if activeTextField === textField {
                activeTextField = nil
            }
            let newValue = textField.text ?? ""
            if parent.text != newValue {
                parent.text = newValue
            }
            if parent.isFocused?.wrappedValue == true {
                DispatchQueue.main.async {
                    if self.parent.isFocused?.wrappedValue == true {
                        self.parent.isFocused?.wrappedValue = false
                    }
                }
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            DispatchQueue.main.async {
                self.parent.submitAction()
            }
            return false
        }
    }
}

private struct ShadowClientPlatformUIKitTextView: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let accessibilityIdentifier: String?
    let accessibilityLabel: String?
    let textOpacity: Double
    let usesMonospacedFont: Bool
    let fontWeight: ShadowClientPlatformTextFieldWeight
    let showsDoneToolbar: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PlaceholderTextView {
        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.tintColor = .white
        textView.autocapitalizationType = .sentences
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
        textView.smartInsertDeleteType = .yes
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.inputAssistantItem.leadingBarButtonGroups = []
        textView.inputAssistantItem.trailingBarButtonGroups = []
        if showsDoneToolbar {
            textView.inputAccessoryView = context.coordinator.makeDoneToolbar()
        }
        textView.textContainerInset = UIEdgeInsets(top: 8, left: -2, bottom: 8, right: -2)
        textView.placeholder = placeholder
        textView.accessibilityIdentifier = accessibilityIdentifier
        textView.accessibilityLabel = accessibilityLabel
        configure(textView)
        textView.text = text
        textView.updatePlaceholderVisibility()
        return textView
    }

    func updateUIView(_ textView: PlaceholderTextView, context: Context) {
        context.coordinator.parent = self
        if textView.markedTextRange == nil, textView.text != text {
            textView.text = text
        }
        configure(textView)
        textView.updatePlaceholderVisibility()
    }

    private func configure(_ textView: UITextView) {
        textView.textColor = UIColor.white.withAlphaComponent(textOpacity)
        textView.font = usesMonospacedFont
            ? UIFont.monospacedSystemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: fontWeight.uiKitValue
            )
            : UIFont.systemFont(
                ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
                weight: fontWeight.uiKitValue
            )
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ShadowClientPlatformUIKitTextView
        weak var activeTextView: UITextView?

        init(_ parent: ShadowClientPlatformUIKitTextView) {
            self.parent = parent
        }

        func makeDoneToolbar() -> UIToolbar {
            let toolbar = UIToolbar()
            toolbar.sizeToFit()
            toolbar.items = [
                UIBarButtonItem(systemItem: .flexibleSpace),
                UIBarButtonItem(
                    barButtonSystemItem: .done,
                    target: self,
                    action: #selector(didTapDone)
                ),
            ]
            return toolbar
        }

        @objc func didTapDone() {
            activeTextView?.resignFirstResponder()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            activeTextView = textView
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if activeTextView === textView {
                activeTextView = nil
            }
            let newValue = textView.text ?? ""
            if parent.text != newValue {
                parent.text = newValue
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            if textView.markedTextRange != nil {
                (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
                return
            }
            let newValue = textView.text ?? ""
            if parent.text != newValue {
                parent.text = newValue
            }
            (textView as? PlaceholderTextView)?.updatePlaceholderVisibility()
        }
    }
}

private final class PlaceholderTextView: UITextView {
    private let placeholderLabel = UILabel()

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        placeholderLabel.textColor = UIColor.white.withAlphaComponent(0.35)
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !(text?.isEmpty ?? true)
    }
}

private extension ShadowClientPlatformTextFieldAlignment {
    var uiKitValue: NSTextAlignment {
        switch self {
        case .leading:
            .left
        case .center:
            .center
        case .trailing:
            .right
        }
    }
}

private extension ShadowClientPlatformTextFieldKeyboardType {
    var uiKitValue: UIKeyboardType {
        switch self {
        case .standard:
            .default
        case .url:
            .URL
        case .ascii:
            .asciiCapable
        case .numberPad:
            .numberPad
        }
    }
}

private extension ShadowClientPlatformTextFieldSubmitLabel {
    var uiKitValue: UIReturnKeyType {
        switch self {
        case .done:
            .done
        case .next:
            .next
        }
    }
}

private extension ShadowClientPlatformTextFieldWeight {
    var uiKitValue: UIFont.Weight {
        switch self {
        case .regular:
            .regular
        case .semibold:
            .semibold
        case .bold:
            .bold
        }
    }
}
#endif
