import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowUIFoundation
import ShadowClientFeatureSession

extension ShadowClientAppShellView {
    var homeTab: some View {
        ZStack {
            backgroundGradient
            ScrollView {
                VStack(spacing: ShadowClientAppShellChrome.Metrics.homeSectionSpacing) {
                    remoteDesktopHostCard
                    connectionStatusCard

                    ShadowClientFeatureHomeView(
                        platformName: platformName,
                        dependencies: baseDependencies.applying(settings: currentSettings),
                        connectionState: connectionState,
                        showsDiagnosticsHUD: currentSettings.showDiagnosticsHUD
                    )
                    .id(currentSettings.streamingIdentityKey)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, ShadowClientAppShellChrome.Metrics.screenBottomPadding)
            }
            .scrollContentBackground(.hidden)

            if let spotlightedHost = spotlightedRemoteDesktopHost {
                GeometryReader { proxy in
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissHostSpotlight()
                            }

                        remoteDesktopHostSpotlightCard(spotlightedHost, containerSize: proxy.size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
                .allowsHitTesting(true)
                .zIndex(10)
            }
        }
        .coordinateSpace(name: "shadow.home.spotlightSpace")
        .accessibilityIdentifier("shadow.tab.home")
        .tabItem { Label("Home", systemImage: "house.fill") }
        .tag(AppTab.home)
    }
}
