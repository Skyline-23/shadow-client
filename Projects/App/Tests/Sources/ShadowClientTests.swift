import ShadowClientFeatureHome
import Testing

struct ShadowClientTests {
    @MainActor
    static func makeHomeView() -> ShadowClientFeatureHomeView {
        ShadowClientFeatureHomeView(
            platformName: "Tests",
            dependencies: .preview()
        )
    }
}
