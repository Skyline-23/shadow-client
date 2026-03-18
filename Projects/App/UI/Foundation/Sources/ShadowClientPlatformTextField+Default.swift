#if !os(iOS) && !os(tvOS)
import SwiftUI

extension ShadowClientPlatformTextField {
    var platformBody: some View {
        TextField(placeholder, text: $text)
            .font(font)
            .textFieldStyle(.plain)
            .foregroundStyle(.white.opacity(textOpacity))
            .autocorrectionDisabled(true)
            .textContentType(.none)
            .multilineTextAlignment(textAlignment.swiftUIValue)
            .modifier(ShadowClientPlatformFocusModifier(isFocused: isFocused))
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
            .accessibilityLabel(accessibilityLabel ?? "")
            .submitLabel(submitLabel.swiftUIValue)
            .onSubmit(submitAction)
    }
}

extension ShadowClientPlatformTextView {
    var platformBody: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .font(font)
            .textFieldStyle(.plain)
            .foregroundStyle(.white.opacity(textOpacity))
            .autocorrectionDisabled(false)
            .textContentType(.none)
            .lineLimit(2...4)
            .accessibilityIdentifier(accessibilityIdentifier ?? "")
            .accessibilityLabel(accessibilityLabel ?? "")
    }
}

private struct ShadowClientPlatformFocusModifier: ViewModifier {
    let isFocused: Binding<Bool>?

    func body(content: Content) -> some View {
        content
    }
}

private extension ShadowClientPlatformTextField {
    var font: Font {
        let weight = fontWeight.swiftUIValue
        if usesMonospacedFont {
            return .system(.body, design: .monospaced).weight(weight)
        }
        return .system(.body).weight(weight)
    }
}

private extension ShadowClientPlatformTextView {
    var font: Font {
        let weight = fontWeight.swiftUIValue
        if usesMonospacedFont {
            return .system(.body, design: .monospaced).weight(weight)
        }
        return .system(.body).weight(weight)
    }
}

private extension ShadowClientPlatformTextFieldAlignment {
    var swiftUIValue: TextAlignment {
        switch self {
        case .leading:
            .leading
        case .center:
            .center
        case .trailing:
            .trailing
        }
    }
}

private extension ShadowClientPlatformTextFieldSubmitLabel {
    var swiftUIValue: SubmitLabel {
        switch self {
        case .done:
            .done
        case .next:
            .next
        }
    }
}

private extension ShadowClientPlatformTextFieldWeight {
    var swiftUIValue: Font.Weight {
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
