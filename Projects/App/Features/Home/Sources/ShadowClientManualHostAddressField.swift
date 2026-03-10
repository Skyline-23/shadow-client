import SwiftUI

struct ShadowClientManualHostAddressField: View {
    @Binding var text: String
    let isFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
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
        .task {
            await Task.yield()
            isFocused.wrappedValue = true
        }
        .onDisappear {
            isFocused.wrappedValue = false
        }
    }
}
