import SwiftUI

public struct ShadowUIRemoteSessionHUDCard<Content: View>: View {
    private let width: CGFloat
    private let content: Content

    public init(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.width = width
        self.content = content()
    }

    public var body: some View {
        content
            .padding(10)
            .frame(width: width, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
    }
}

public struct ShadowUIRemoteSessionStatChip: View {
    private let label: String
    private let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(alignment: .center, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.center)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .center)
    }
}
