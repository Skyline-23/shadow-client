#if !os(macOS)
import SwiftUI

struct ShadowClientDisplayMetricsObserver: View {
    let onMetricsChanged: @MainActor (ShadowClientDisplayMetricsState) -> Void

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                await MainActor.run {
                    onMetricsChanged(.default)
                }
            }
    }
}
#endif
