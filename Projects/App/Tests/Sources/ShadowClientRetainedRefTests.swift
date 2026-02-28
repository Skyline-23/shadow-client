import Testing
@testable import ShadowClientFeatureHome

private final class ShadowClientRetainedRefProbe {
    private let onDeinit: @Sendable () -> Void

    init(onDeinit: @escaping @Sendable () -> Void) {
        self.onDeinit = onDeinit
    }

    deinit {
        onDeinit()
    }
}

@Test("RetainedRef holds object until explicit release")
func retainedRefHoldsObjectUntilRelease() {
    final class DeinitState: @unchecked Sendable {
        var didDeinit = false
    }

    let deinitState = DeinitState()
    var probe: ShadowClientRetainedRefProbe? = ShadowClientRetainedRefProbe {
        deinitState.didDeinit = true
    }

    let opaque = ShadowClientRetainedRef.retain(probe!)
    probe = nil
    #expect(deinitState.didDeinit == false)

    ShadowClientRetainedRef.release(opaque, as: ShadowClientRetainedRefProbe.self)
    #expect(deinitState.didDeinit == true)
}

@Test("RetainedRef unretained lookup returns same instance")
func retainedRefUnretainedLookupReturnsSameInstance() {
    let probe = ShadowClientRetainedRefProbe {}
    let opaque = ShadowClientRetainedRef.retain(probe)
    let lookedUp: ShadowClientRetainedRefProbe = ShadowClientRetainedRef.unretainedValue(from: opaque)
    #expect(lookedUp === probe)
    ShadowClientRetainedRef.release(opaque, as: ShadowClientRetainedRefProbe.self)
}
