import ShadowClientStreaming
import SwiftUI

@main
struct ShadowClientmacOSApp: App {
    private let telemetryBridge: MoonlightSessionTelemetryBridge

    init() {
        let bridge = MoonlightSessionTelemetryBridge()
        self.telemetryBridge = bridge
        MoonlightSessionTelemetryIngress.configure(bridge: bridge)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: .live(bridge: telemetryBridge)
            )
        }
    }
}
