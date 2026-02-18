import SwiftUI

public struct ShadowClientRealtimeSessionSurfaceView: View {
    @ObservedObject private var surfaceContext: ShadowClientRealtimeSessionSurfaceContext

    public init(context: ShadowClientRealtimeSessionSurfaceContext) {
        _surfaceContext = ObservedObject(wrappedValue: context)
    }

    public var body: some View {
        ShadowClientRealtimeSessionSurfaceRepresentable(surfaceContext: surfaceContext)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("remote-desktop-native-surface")
            .accessibilityLabel("Remote desktop native surface")
    }
}
