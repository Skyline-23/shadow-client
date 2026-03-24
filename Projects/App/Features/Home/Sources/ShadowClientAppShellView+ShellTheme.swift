import SwiftUI

extension ShadowClientAppShellView {
    var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.08, blue: 0.15),
                    Color(red: 0.06, green: 0.16, blue: 0.20),
                    Color(red: 0.13, green: 0.14, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accentColor.opacity(0.26),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.18),
                    .clear,
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    var accentColor: Color {
        Color(red: 0.34, green: 0.88, blue: 0.82)
    }
}
