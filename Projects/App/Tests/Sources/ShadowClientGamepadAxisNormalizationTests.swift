import Testing
@testable import ShadowClientFeatureHome

@Test("Gamepad stick normalization preserves axis sign")
func gamepadStickNormalizationPreservesAxisSign() {
    #expect(ShadowClientGamepadInputPassthroughRuntime.normalizeStickAxisValue(0.65) > 0)
    #expect(ShadowClientGamepadInputPassthroughRuntime.normalizeStickAxisValue(-0.65) < 0)
}

@Test("Gamepad stick normalization clamps out-of-range values")
func gamepadStickNormalizationClampsOutOfRangeValues() {
    #expect(ShadowClientGamepadInputPassthroughRuntime.normalizeStickAxisValue(1.5) == 32767)
    #expect(ShadowClientGamepadInputPassthroughRuntime.normalizeStickAxisValue(-1.5) == -32767)
}
