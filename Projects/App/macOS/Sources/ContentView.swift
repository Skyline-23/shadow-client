import ShadowClientFeatureHome
import SwiftUI

struct ContentView: View {
    private let dependencies: ShadowClientFeatureHomeDependencies

    init(dependencies: ShadowClientFeatureHomeDependencies) {
        self.dependencies = dependencies
    }

    var body: some View {
        ShadowClientFeatureHomeView(platformName: "macOS", dependencies: dependencies)
    }
}
