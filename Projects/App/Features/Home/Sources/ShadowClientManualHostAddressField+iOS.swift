#if os(iOS) || os(tvOS)
import SwiftUI

private struct ShadowClientManualHostAddressFieldPlatformModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            .keyboardType(.URL)
    }
}

extension View {
    func shadowClientManualHostAddressFieldPlatformBehavior() -> some View {
        modifier(ShadowClientManualHostAddressFieldPlatformModifier())
    }
}
#endif
