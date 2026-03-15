import SwiftUI

public struct ShadowUIRemoteSessionConnectionIssueHUD: View {
    private let title: String
    private let message: String
    private let badgeText: String
    private let footnote: String

    public init(title: String, message: String, badgeText: String, footnote: String) {
        self.title = title
        self.message = message
        self.badgeText = badgeText
        self.footnote = footnote
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(Color.red.opacity(0.95))
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.95))
                Spacer(minLength: 8)
                Text(badgeText)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.95))
            }

            Text(message)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.82))
                .lineLimit(3)

            Text(footnote)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.red.opacity(0.90))
        }
    }
}
