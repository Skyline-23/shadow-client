import SwiftUI

public struct ShadowClientRealtimeSessionSurfaceView: View {
    public init() {}

    public var body: some View {
        ShadowClientRealtimeSessionSurfaceRepresentable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("remote-desktop-native-surface")
            .accessibilityLabel("Remote desktop native surface")
    }
}
