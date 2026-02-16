import ShadowClientFeatureHome
import Testing

struct ShadowClientTests {
    static func makeHomeView() -> ShadowClientFeatureHomeView {
        ShadowClientFeatureHomeView(platformName: "Tests")
    }
}
