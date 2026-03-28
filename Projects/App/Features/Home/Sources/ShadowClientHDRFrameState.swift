import Foundation

public enum ShadowClientHDRFrameContent: UInt8, Equatable, Sendable {
    case sdr = 0
    case fullFrameHDR = 1
    case partialHDROverlay = 2
}

public struct ShadowClientHDROverlayRegion: Equatable, Sendable {
    let x: UInt16
    let y: UInt16
    let width: UInt16
    let height: UInt16
    let metadata: ShadowClientHDRMetadata?

    var debugSummary: String {
        "x=\(x) y=\(y) width=\(width) height=\(height) metadata=\(metadata?.debugSummary ?? "nil")"
    }
}

public struct ShadowClientHDRFrameState: Equatable, Sendable {
    let content: ShadowClientHDRFrameContent
    let effectiveFromFrameNumber: UInt32
    let staticMetadata: ShadowClientHDRMetadata?
    let overlayRegions: [ShadowClientHDROverlayRegion]

    var isDynamicRangeEnabled: Bool {
        content != .sdr
    }

    func resolvedMetadata(fallback: ShadowClientHDRMetadata?) -> ShadowClientHDRMetadata? {
        staticMetadata ?? fallback
    }

    var debugSummary: String {
        let overlaySummary = overlayRegions.map(\.debugSummary).joined(separator: ";")
        return "content=\(content) effective-frame=\(effectiveFromFrameNumber) static-metadata=\(staticMetadata?.debugSummary ?? "nil") overlay-regions=[\(overlaySummary)]"
    }
}
