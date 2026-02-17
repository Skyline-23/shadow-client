import ShadowClientStreaming
import SwiftUI
import ShadowClientFeatureHome

@main
struct ShadowClientiOSApp: App {
    private let container: ShadowClientFeatureHomeContainer

    init() {
        let bridge = MoonlightSessionTelemetryBridge()
        MoonlightSessionTelemetryIngress.configure(bridge: bridge)
        self.container = .live(bridge: bridge)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: container.dependencies
            )
        }
    }
}
