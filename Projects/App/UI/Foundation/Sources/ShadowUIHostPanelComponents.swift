import SwiftUI

public enum ShadowUIHostPanelPalette {
    public static let panelInsetSurface = Color(red: 0.17, green: 0.20, blue: 0.26)
    public static let headerBadgeSurface = Color(red: 0.20, green: 0.24, blue: 0.30)
    public static let spotlightInsetSurface = Color(red: 0.12, green: 0.15, blue: 0.21)
    public static let spotlightBadgeSurface = Color(red: 0.16, green: 0.11, blue: 0.14)
}

public struct ShadowUIHostCalloutRow: View {
    private let title: String
    private let message: String
    private let accent: Color

    public init(title: String, message: String, accent: Color) {
        self.title = title
        self.message = message
        self.accent = accent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ShadowUIHostPanelPalette.spotlightInsetSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
    }
}
