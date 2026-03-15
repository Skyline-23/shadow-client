import SwiftUI

public struct ShadowUIHostInsetField<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(ShadowUIHostPanelPalette.spotlightInsetSurface)
            )
    }
}

public struct ShadowUIHostInsetCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ShadowUIHostPanelPalette.spotlightInsetSurface)
            )
    }
}
