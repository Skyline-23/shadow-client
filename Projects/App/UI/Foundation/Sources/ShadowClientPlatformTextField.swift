import SwiftUI

public enum ShadowClientPlatformTextFieldAlignment {
    case leading
    case center
    case trailing
}

public enum ShadowClientPlatformTextFieldKeyboardType {
    case standard
    case url
    case ascii
    case numberPad
}

public enum ShadowClientPlatformTextFieldSubmitLabel {
    case done
    case next
}

public enum ShadowClientPlatformTextFieldWeight {
    case regular
    case semibold
    case bold
}

public struct ShadowClientPlatformTextField: View {
    @Binding public var text: String
    public let placeholder: String
    public let isFocused: Binding<Bool>?
    public let accessibilityIdentifier: String?
    public let accessibilityLabel: String?
    public let submitAction: () -> Void
    public let textAlignment: ShadowClientPlatformTextFieldAlignment
    public let keyboardType: ShadowClientPlatformTextFieldKeyboardType
    public let submitLabel: ShadowClientPlatformTextFieldSubmitLabel
    public let showsDoneToolbar: Bool
    public let textOpacity: Double
    public let usesMonospacedFont: Bool
    public let fontWeight: ShadowClientPlatformTextFieldWeight
    public let isSecureTextEntry: Bool

    public init(
        text: Binding<String>,
        placeholder: String,
        isFocused: Binding<Bool>? = nil,
        accessibilityIdentifier: String? = nil,
        accessibilityLabel: String? = nil,
        submitAction: @escaping () -> Void = {},
        textAlignment: ShadowClientPlatformTextFieldAlignment = .leading,
        keyboardType: ShadowClientPlatformTextFieldKeyboardType = .standard,
        submitLabel: ShadowClientPlatformTextFieldSubmitLabel = .done,
        showsDoneToolbar: Bool = false,
        textOpacity: Double = 1,
        usesMonospacedFont: Bool = false,
        fontWeight: ShadowClientPlatformTextFieldWeight = .regular,
        isSecureTextEntry: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isFocused = isFocused
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.submitAction = submitAction
        self.textAlignment = textAlignment
        self.keyboardType = keyboardType
        self.submitLabel = submitLabel
        self.showsDoneToolbar = showsDoneToolbar
        self.textOpacity = textOpacity
        self.usesMonospacedFont = usesMonospacedFont
        self.fontWeight = fontWeight
        self.isSecureTextEntry = isSecureTextEntry
    }

    public var body: some View {
        platformBody
    }
}

public struct ShadowClientPlatformTextView: View {
    @Binding public var text: String
    public let placeholder: String
    public let accessibilityIdentifier: String?
    public let accessibilityLabel: String?
    public let textOpacity: Double
    public let usesMonospacedFont: Bool
    public let fontWeight: ShadowClientPlatformTextFieldWeight
    public let showsDoneToolbar: Bool

    public init(
        text: Binding<String>,
        placeholder: String,
        accessibilityIdentifier: String? = nil,
        accessibilityLabel: String? = nil,
        textOpacity: Double = 1,
        usesMonospacedFont: Bool = false,
        fontWeight: ShadowClientPlatformTextFieldWeight = .regular,
        showsDoneToolbar: Bool = false
    ) {
        self._text = text
        self.placeholder = placeholder
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.textOpacity = textOpacity
        self.usesMonospacedFont = usesMonospacedFont
        self.fontWeight = fontWeight
        self.showsDoneToolbar = showsDoneToolbar
    }

    public var body: some View {
        platformBody
    }
}
