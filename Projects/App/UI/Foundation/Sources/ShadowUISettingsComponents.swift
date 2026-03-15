import SwiftUI

public struct ShadowUISettingsSection<Content: View>: View {
    private let title: String
    private let content: Content

    public init(
        title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ShadowClientAppShellChrome.Metrics.sectionHeaderSpacing) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: ShadowClientAppShellChrome.Metrics.sectionContentSpacing) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ShadowClientAppShellChrome.Metrics.sectionPadding)
        .background(
            RoundedRectangle(cornerRadius: ShadowClientAppShellChrome.Metrics.panelCornerRadius, style: .continuous)
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
                    RoundedRectangle(cornerRadius: ShadowClientAppShellChrome.Metrics.panelCornerRadius, style: .continuous)
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
    }
}

public struct ShadowUISettingsRow<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: ShadowClientAppShellChrome.Metrics.rowSpacing) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ShadowClientAppShellChrome.Metrics.rowHorizontalPadding)
        .padding(.vertical, ShadowClientAppShellChrome.Metrics.rowVerticalPadding)
        .background(rowBackground)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: ShadowClientAppShellChrome.Metrics.rowCornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        ShadowClientAppShellChrome.Palette.rowGradientTop,
                        ShadowClientAppShellChrome.Palette.rowGradientBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: ShadowClientAppShellChrome.Metrics.rowCornerRadius, style: .continuous)
                    .stroke(
                        ShadowClientAppShellChrome.Palette.rowStroke,
                        lineWidth: ShadowClientAppShellChrome.Metrics.rowStrokeWidth
                    )
            )
    }
}

public struct ShadowUISettingsPickerRow<Value: Hashable, Content: View>: View {
    private let title: String
    private let symbol: String
    private let selection: Binding<Value>
    private let options: Content

    public init(
        title: String,
        symbol: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.selection = selection
        self.options = content()
    }

    public var body: some View {
        ShadowUISettingsRow {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Picker(title, selection: selection) {
                    options
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Spacer(minLength: 0)
        }
    }
}

public struct ShadowUIDiagnosticsRow: View {
    private let label: String
    private let value: String
    private let valueColor: Color

    public init(label: String, value: String, valueColor: Color = Color.white.opacity(0.92)) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
    }

    public var body: some View {
        ShadowUISettingsRow {
            Text(label)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(ShadowClientAppShellChrome.Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }
}
