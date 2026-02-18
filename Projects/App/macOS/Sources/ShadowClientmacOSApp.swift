import ShadowClientStreaming
import SwiftUI
import ShadowClientFeatureHome

@main
struct ShadowClientmacOSApp: App {
    private let container: ShadowClientFeatureHomeContainer

    init() {
        let bridge = MoonlightSessionTelemetryBridge()
        MoonlightSessionTelemetryIngress.configure(bridge: bridge)
        self.container = .live(
            bridge: bridge,
            connectionClient: NativeHostProbeConnectionClient(),
            remoteDesktopDependencies: .live(
                sessionConnectionClient: ShadowClientmacOSMoonlightSessionConnectionClient()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: container.dependencies
            )
        }
    }
}
