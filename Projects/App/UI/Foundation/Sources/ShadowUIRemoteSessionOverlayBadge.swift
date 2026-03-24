import SwiftUI

public struct ShadowUIRemoteSessionOverlayBadge: View {
    private let title: String
    private let symbol: String
    private let textColor: Color
    private let backgroundOpacity: Double
    private let strokeOpacity: Double
    private let width: CGFloat
    private let animatesSymbol: Bool
    private let showsActivityIndicator: Bool

    @State private var isAnimating = false

    public init(
        title: String,
        symbol: String,
        textColor: Color,
        backgroundOpacity: Double,
        strokeOpacity: Double,
        width: CGFloat,
        animatesSymbol: Bool,
        showsActivityIndicator: Bool = false
    ) {
        self.title = title
        self.symbol = symbol
        self.textColor = textColor
        self.backgroundOpacity = backgroundOpacity
        self.strokeOpacity = strokeOpacity
        self.width = width
        self.animatesSymbol = animatesSymbol
        self.showsActivityIndicator = showsActivityIndicator
    }

    public var body: some View {
        HStack(spacing: 12) {
            if showsActivityIndicator {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(textColor)
                    .controlSize(.regular)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(textColor)
                    .rotationEffect(.degrees(animatesSymbol && isAnimating ? 360 : 0))
                    .animation(
                        animatesSymbol
                            ? .linear(duration: 1.1).repeatForever(autoreverses: false)
                            : .default,
                        value: isAnimating
                    )
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(textColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .frame(maxWidth: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(backgroundOpacity))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(textColor.opacity(strokeOpacity), lineWidth: 0.9)
        )
        .shadow(color: Color.black.opacity(0.22), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 24)
        .onAppear {
            guard animatesSymbol, !showsActivityIndicator else {
                return
            }
            isAnimating = true
        }
        .onDisappear {
            isAnimating = false
        }
    }
}
