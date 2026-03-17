import SwiftUI

public struct ShadowClientManualHostAddressField: View {
    @Binding public var text: String
    public let isFocused: FocusState<Bool>.Binding
    public let onSubmit: () -> Void

    public init(text: Binding<String>, isFocused: FocusState<Bool>.Binding, onSubmit: @escaping () -> Void) {
        self._text = text
        self.isFocused = isFocused
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "network")
                .foregroundStyle(Color.white.opacity(0.60))
            TextField("Host, IP, or URL", text: $text)
                .font(.body.monospaced().weight(.semibold))
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .autocorrectionDisabled(true)
                .focused(isFocused)
                .accessibilityIdentifier("shadow.home.hosts.manual-entry")
                .accessibilityLabel("Remote host address")
                .shadowClientManualHostAddressFieldPlatformBehavior()
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onDisappear {
            isFocused.wrappedValue = false
        }
    }
}
