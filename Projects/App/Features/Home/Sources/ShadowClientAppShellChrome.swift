import SwiftUI

enum ShadowClientAppShellChrome {
    enum Metrics {
        static let homeSectionSpacing: CGFloat = 28
        static let settingsSectionSpacing: CGFloat = 18
        static let sectionHeaderSpacing: CGFloat = 12
        static let sectionContentSpacing: CGFloat = 10
        static let sectionPadding: CGFloat = 16
        static let rowSpacing: CGFloat = 10
        static let rowHorizontalPadding: CGFloat = 12
        static let rowVerticalPadding: CGFloat = 10
        static let panelCornerRadius: CGFloat = 14
        static let rowCornerRadius: CGFloat = 10
        static let screenBottomPadding: CGFloat = 40
        static let connectionStatusPadding: CGFloat = 14
        static let connectionIndicatorSize: CGFloat = 10
        static let panelShadowRadius: CGFloat = 18
        static let panelShadowY: CGFloat = 10
        static let panelStrokeWidth: CGFloat = 1
        static let rowStrokeWidth: CGFloat = 0.8
    }

    enum Palette {
        static let panelGradientTop = Color.white.opacity(0.12)
        static let panelGradientBottom = Color.white.opacity(0.06)
        static let panelStroke = Color.white.opacity(0.16)
        static let panelShadow = Color.black.opacity(0.28)

        static let rowGradientTop = Color.black.opacity(0.30)
        static let rowGradientBottom = Color.black.opacity(0.22)
        static let rowStroke = Color.white.opacity(0.14)

        static let secondaryText = Color.white.opacity(0.75)
        static let tertiaryText = Color.white.opacity(0.74)
        static let quaternaryText = Color.white.opacity(0.72)
        static let connectionText = Color.white.opacity(0.82)
    }
}
