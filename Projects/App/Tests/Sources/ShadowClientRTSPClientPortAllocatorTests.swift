import Network
import Testing
@testable import ShadowClientFeatureHome

@Test("RTSP client port allocator keeps preferred base when pair is available")
func rtspClientPortAllocatorKeepsPreferredBaseWhenAvailable() {
    let selected = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
        preferred: 50_000,
        localHost: nil,
        attemptCount: 4,
        isPortAvailable: { _, _ in true }
    )

    #expect(selected == 50_000)
}

@Test("RTSP client port allocator skips occupied pair and selects next available even base")
func rtspClientPortAllocatorSkipsOccupiedPair() {
    let selected = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
        preferred: 50_000,
        localHost: nil,
        attemptCount: 4,
        isPortAvailable: { _, port in
            ![50_000, 50_001].contains(port)
        }
    )

    #expect(selected == 50_002)
}

@Test("RTSP client port allocator normalizes odd preferred base to even base")
func rtspClientPortAllocatorNormalizesOddBase() {
    let selected = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
        preferred: 50_001,
        localHost: nil,
        attemptCount: 1,
        isPortAvailable: { _, _ in false }
    )

    #expect(selected == 50_000)
}

@Test("RTSP client port allocator falls back to preferred base when no candidate is available")
func rtspClientPortAllocatorFallsBackToPreferredBaseWhenNoCandidateIsAvailable() {
    let selected = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
        preferred: 50_000,
        localHost: nil,
        attemptCount: 3,
        isPortAvailable: { _, _ in false }
    )

    #expect(selected == 50_000)
}

@Test("RTSP client port allocator tolerates IPv4 hosts with interface scope suffixes")
func rtspClientPortAllocatorToleratesScopedIPv4Hosts() {
    let selected = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
        preferred: 50_000,
        localHost: .init("192.168.0.62%en0"),
        attemptCount: 1,
        isPortAvailable: { _, _ in true }
    )

    #expect(selected == 50_000)
}
