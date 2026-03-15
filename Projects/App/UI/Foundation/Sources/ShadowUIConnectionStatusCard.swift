import SwiftUI

public struct ShadowUIConnectionStatusCard: View {
    private let title: String
    private let statusText: String
    private let indicatorColor: Color

    public init(title: String, statusText: String, indicatorColor: Color) {
        self.title = title
        self.statusText = statusText
        self.indicatorColor = indicatorColor
    }

    public var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(indicatorColor)
                .frame(width: ShadowClientAppShellChrome.Metrics.connectionIndicatorSize, height: ShadowClientAppShellChrome.Metrics.connectionIndicatorSize)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(ShadowClientAppShellChrome.Palette.connectionText)
            }

            Spacer(minLength: 0)
        }
        .padding(ShadowClientAppShellChrome.Metrics.connectionStatusPadding)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            ShadowClientAppShellChrome.Palette.panelGradientTop,
                            ShadowClientAppShellChrome.Palette.panelGradientBottom,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            ShadowClientAppShellChrome.Palette.panelStroke,
                            lineWidth: ShadowClientAppShellChrome.Metrics.panelStrokeWidth
                        )
                )
                .shadow(
                    color: ShadowClientAppShellChrome.Palette.panelShadow,
                    radius: ShadowClientAppShellChrome.Metrics.panelShadowRadius,
                    x: 0,
                    y: ShadowClientAppShellChrome.Metrics.panelShadowY
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(statusText)
    }
}
