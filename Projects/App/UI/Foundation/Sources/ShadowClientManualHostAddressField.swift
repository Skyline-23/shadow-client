import SwiftUI
#if os(iOS) || os(tvOS)
import UIKit
#endif

public struct ShadowClientManualHostAddressField: View {
    public enum FocusField: Hashable {
        case host
        case port
    }

    @Binding public var text: String
    @Binding public var portText: String
    public let focusedField: FocusState<FocusField?>.Binding
    public let onSubmit: () -> Void
    @State private var requestedFocusField: FocusField?

    public init(
        text: Binding<String>,
        portText: Binding<String>,
        focusedField: FocusState<FocusField?>.Binding,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self._portText = portText
        self.focusedField = focusedField
        self.onSubmit = onSubmit
    }

    public var body: some View {
        fieldContent
            .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
            .padding(.leading, 8)
    }

    @ViewBuilder
    private var fieldContent: some View {
        #if os(iOS) || os(tvOS)
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(Color.white.opacity(0.60))
            ShadowClientManualHostUIKitField(
                text: $text,
                placeholder: "Host, IP, or URL",
                keyboardType: .URL,
                returnKeyType: .next,
                textAlignment: .left,
                textOpacity: 1,
                digitsOnly: false,
                accessibilityIdentifier: "shadow.home.hosts.manual-entry",
                accessibilityLabel: "Remote host address",
                requestedFocusField: $requestedFocusField,
                fieldID: .host,
                onFocusChange: { isFocused in
                    if isFocused {
                        focusedField.wrappedValue = .host
                    } else if focusedField.wrappedValue == .host {
                        focusedField.wrappedValue = nil
                    }
                },
                onReturn: {
                    requestedFocusField = .port
                }
            )
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: 22)

            ShadowClientManualHostUIKitField(
                text: $portText,
                placeholder: "Port",
                keyboardType: .numbersAndPunctuation,
                returnKeyType: .done,
                textAlignment: .left,
                textOpacity: 0.88,
                digitsOnly: true,
                accessibilityIdentifier: "shadow.home.hosts.manual-entry.port",
                accessibilityLabel: "Remote host port",
                requestedFocusField: $requestedFocusField,
                fieldID: .port,
                onFocusChange: { isFocused in
                    if isFocused {
                        focusedField.wrappedValue = .port
                    } else if focusedField.wrappedValue == .port {
                        focusedField.wrappedValue = nil
                    }
                },
                onReturn: {
                    requestedFocusField = nil
                    onSubmit()
                }
            )
            .frame(width: 64)
        }
        #else
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(Color.white.opacity(0.60))
            ShadowClientPlatformTextField(
                text: $text,
                placeholder: "Host, IP, or URL",
                isFocused: hostFocusBinding,
                accessibilityIdentifier: "shadow.home.hosts.manual-entry",
                accessibilityLabel: "Remote host address",
                submitAction: {
                    focusedField.wrappedValue = .port
                },
                keyboardType: .url,
                submitLabel: .next,
                usesMonospacedFont: true,
                fontWeight: .semibold
            )
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1, height: 22)
            ShadowClientPlatformTextField(
                text: $portText,
                placeholder: "Port",
                isFocused: portFocusBinding,
                accessibilityIdentifier: "shadow.home.hosts.manual-entry.port",
                accessibilityLabel: "Remote host port",
                submitAction: onSubmit,
                textAlignment: .trailing,
                keyboardType: .numberPad,
                showsDoneToolbar: true,
                textOpacity: 0.88,
                usesMonospacedFont: true,
                fontWeight: .semibold
            )
            .frame(width: 74)
            .onChange(of: portText) { _, newValue in
                let digitsOnly = String(newValue.filter(\.isNumber).prefix(5))
                if digitsOnly != newValue {
                    portText = digitsOnly
                }
            }
        }
        #endif
    }

    private var hostFocusBinding: Binding<Bool> {
        Binding(
            get: { focusedField.wrappedValue == .host },
            set: { isFocused in
                if isFocused {
                    focusedField.wrappedValue = .host
                } else if focusedField.wrappedValue == .host {
                    focusedField.wrappedValue = nil
                }
            }
        )
    }

    private var portFocusBinding: Binding<Bool> {
        Binding(
            get: { focusedField.wrappedValue == .port },
            set: { isFocused in
                if isFocused {
                    focusedField.wrappedValue = .port
                } else if focusedField.wrappedValue == .port {
                    focusedField.wrappedValue = nil
                }
            }
        )
    }
}

#if os(iOS) || os(tvOS)
private struct ShadowClientManualHostUIKitField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let keyboardType: UIKeyboardType
    let returnKeyType: UIReturnKeyType
    let textAlignment: NSTextAlignment
    let textOpacity: Double
    let digitsOnly: Bool
    let accessibilityIdentifier: String
    let accessibilityLabel: String
    @Binding var requestedFocusField: ShadowClientManualHostAddressField.FocusField?
    let fieldID: ShadowClientManualHostAddressField.FocusField
    let onFocusChange: (Bool) -> Void
    let onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> EdgeInsetTextField {
        let textField = EdgeInsetTextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.tintColor = .white
        textField.textColor = UIColor.white.withAlphaComponent(textOpacity)
        textField.font = UIFont.monospacedSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .semibold
        )
        textField.placeholder = placeholder
        textField.text = text
        textField.keyboardType = keyboardType
        textField.returnKeyType = returnKeyType
        textField.textAlignment = textAlignment
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.smartInsertDeleteType = .no
        textField.smartQuotesType = .no
        textField.smartDashesType = .no
        textField.textContentType = nil
        textField.inputAssistantItem.leadingBarButtonGroups = []
        textField.inputAssistantItem.trailingBarButtonGroups = []
        textField.accessibilityIdentifier = accessibilityIdentifier
        textField.accessibilityLabel = accessibilityLabel
        textField.textInsets = UIEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        return textField
    }

    func updateUIView(_ view: EdgeInsetTextField, context: Context) {
        context.coordinator.parent = self
        if view.markedTextRange == nil, view.text != text {
            view.text = text
        }
        view.textColor = UIColor.white.withAlphaComponent(textOpacity)
        if requestedFocusField == fieldID, !view.isFirstResponder {
            DispatchQueue.main.async {
                if self.requestedFocusField == self.fieldID {
                    view.becomeFirstResponder()
                }
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: ShadowClientManualHostUIKitField

        init(_ parent: ShadowClientManualHostUIKitField) {
            self.parent = parent
        }

        @objc func textChanged(_ textField: UITextField) {
            let newValue: String
            if parent.digitsOnly {
                newValue = String((textField.text ?? "").filter(\.isNumber).prefix(5))
                if textField.text != newValue {
                    textField.text = newValue
                }
            } else {
                newValue = textField.text ?? ""
            }
            if parent.text != newValue {
                parent.text = newValue
            }
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.requestedFocusField = nil
            parent.onFocusChange(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            let finalValue: String
            if parent.digitsOnly {
                finalValue = String((textField.text ?? "").filter(\.isNumber).prefix(5))
                textField.text = finalValue
            } else {
                finalValue = textField.text ?? ""
            }
            parent.text = finalValue
            parent.onFocusChange(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onReturn()
            return false
        }
    }
}

private final class EdgeInsetTextField: UITextField {
    var textInsets: UIEdgeInsets = .zero

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: textInsets)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: textInsets)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        bounds.inset(by: textInsets)
    }
}
#endif
