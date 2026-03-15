import SwiftUI

public enum ShadowClientAppShellChrome {
    public enum Metrics {
        public static let homeSectionSpacing: CGFloat = 28
        public static let settingsSectionSpacing: CGFloat = 18
        public static let sectionHeaderSpacing: CGFloat = 12
        public static let sectionContentSpacing: CGFloat = 10
        public static let sectionPadding: CGFloat = 16
        public static let rowSpacing: CGFloat = 10
        public static let rowHorizontalPadding: CGFloat = 12
        public static let rowVerticalPadding: CGFloat = 10
        public static let panelCornerRadius: CGFloat = 14
        public static let rowCornerRadius: CGFloat = 10
        public static let screenBottomPadding: CGFloat = 40
        public static let connectionStatusPadding: CGFloat = 14
        public static let connectionIndicatorSize: CGFloat = 10
        public static let panelShadowRadius: CGFloat = 18
        public static let panelShadowY: CGFloat = 10
        public static let panelStrokeWidth: CGFloat = 1
        public static let rowStrokeWidth: CGFloat = 0.8
    }

    public enum Palette {
        public static let panelGradientTop = Color.white.opacity(0.12)
        public static let panelGradientBottom = Color.white.opacity(0.06)
        public static let panelStroke = Color.white.opacity(0.16)
        public static let panelShadow = Color.black.opacity(0.28)

        public static let rowGradientTop = Color.black.opacity(0.30)
        public static let rowGradientBottom = Color.black.opacity(0.22)
        public static let rowStroke = Color.white.opacity(0.14)

        public static let secondaryText = Color.white.opacity(0.75)
        public static let tertiaryText = Color.white.opacity(0.74)
        public static let quaternaryText = Color.white.opacity(0.72)
        public static let connectionText = Color.white.opacity(0.82)
    }
}
