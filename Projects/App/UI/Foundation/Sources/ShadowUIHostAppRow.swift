import SwiftUI

public struct ShadowUIHostAppRow: View {
    private let title: String
    private let subtitle: String
    private let launchTitle: String
    private let launchAccessibilityLabel: String
    private let launchAccessibilityHint: String
    private let launchAccessibilityIdentifier: String
    private let launchDisabled: Bool
    private let onLaunch: () -> Void

    public init(
        title: String,
        subtitle: String,
        launchTitle: String,
        launchAccessibilityLabel: String,
        launchAccessibilityHint: String,
        launchAccessibilityIdentifier: String,
        launchDisabled: Bool,
        onLaunch: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.launchTitle = launchTitle
        self.launchAccessibilityLabel = launchAccessibilityLabel
        self.launchAccessibilityHint = launchAccessibilityHint
        self.launchAccessibilityIdentifier = launchAccessibilityIdentifier
        self.launchDisabled = launchDisabled
        self.onLaunch = onLaunch
    }

    public var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.68))
            }

            Spacer(minLength: 8)

            Button(launchTitle, action: onLaunch)
                .accessibilityIdentifier(launchAccessibilityIdentifier)
                .accessibilityLabel(launchAccessibilityLabel)
                .accessibilityHint(launchAccessibilityHint)
                .buttonStyle(.borderedProminent)
                .disabled(launchDisabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(ShadowUIHostPanelPalette.spotlightInsetSurface)
        )
    }
}
