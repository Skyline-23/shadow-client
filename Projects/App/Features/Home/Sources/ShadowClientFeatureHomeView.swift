import SwiftUI

public struct ShadowClientFeatureHomeView: View {
    private let platformName: String

    public init(platformName: String) {
        self.platformName = platformName
    }

    public var body: some View {
        VStack(spacing: 8) {
            Text("shadow-client")
                .font(.title2.weight(.semibold))
            Text("Home running on \(platformName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }
}
