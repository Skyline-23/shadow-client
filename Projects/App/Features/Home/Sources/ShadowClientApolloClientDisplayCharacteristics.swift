import Foundation
import CoreGraphics

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

enum ShadowClientApolloClientDisplayGamut: String, Sendable {
    case sRGB = "srgb"
    case displayP3 = "display-p3"
    case rec2020 = "rec2020"
}

enum ShadowClientApolloClientDisplayTransfer: String, Sendable {
    case sdr
    case pq
    case hlg
}

struct ShadowClientApolloClientDisplayCharacteristics: Sendable {
    let gamut: ShadowClientApolloClientDisplayGamut
    let transfer: ShadowClientApolloClientDisplayTransfer
    let scalePercent: Int
    let hiDPIEnabled: Bool
    let currentEDRHeadroom: Float
    let potentialEDRHeadroom: Float
    let currentPeakLuminanceNits: Int
    let potentialPeakLuminanceNits: Int

    init(
        gamut: ShadowClientApolloClientDisplayGamut,
        transfer: ShadowClientApolloClientDisplayTransfer,
        scalePercent: Int,
        hiDPIEnabled: Bool,
        currentEDRHeadroom: Float = 1.0,
        potentialEDRHeadroom: Float = 1.0,
        currentPeakLuminanceNits: Int = 100,
        potentialPeakLuminanceNits: Int = 100
    ) {
        self.gamut = gamut
        self.transfer = transfer
        self.scalePercent = scalePercent
        self.hiDPIEnabled = hiDPIEnabled
        self.currentEDRHeadroom = currentEDRHeadroom
        self.potentialEDRHeadroom = potentialEDRHeadroom
        self.currentPeakLuminanceNits = currentPeakLuminanceNits
        self.potentialPeakLuminanceNits = potentialPeakLuminanceNits
    }
}

enum ShadowClientApolloClientDisplayCharacteristicsResolver {
    @MainActor
    static func current(
        hdrEnabled: Bool,
        scalePercent: Int,
        hiDPIEnabled: Bool
    ) -> ShadowClientApolloClientDisplayCharacteristics {
        #if os(macOS)
        let screen = currentMacScreen()
        let colorSpace = screen?.colorSpace?.cgColorSpace
        let gamut = gamut(for: colorSpace)
        let transfer = macTransferContract(for: colorSpace, hdrEnabled: hdrEnabled)
        let currentEDRHeadroom = currentEDRHeadroom(for: screen)
        let potentialEDRHeadroom = potentialEDRHeadroom(for: screen)
        return .init(
            gamut: gamut,
            transfer: transfer,
            scalePercent: scalePercent,
            hiDPIEnabled: hiDPIEnabled,
            currentEDRHeadroom: currentEDRHeadroom,
            potentialEDRHeadroom: potentialEDRHeadroom,
            currentPeakLuminanceNits: peakLuminanceNits(for: currentEDRHeadroom),
            potentialPeakLuminanceNits: peakLuminanceNits(for: potentialEDRHeadroom)
        )
        #elseif os(iOS) || os(tvOS)
        let screen = currentUIKitScreen() ?? UIScreen.main
        let gamut = gamut(for: screen.traitCollection.displayGamut)
        let transfer: ShadowClientApolloClientDisplayTransfer = hdrEnabled ? .pq : .sdr
        let currentEDRHeadroom = max(Float(screen.currentEDRHeadroom), 1.0)
        let potentialEDRHeadroom = max(Float(screen.potentialEDRHeadroom), 1.0)
        return .init(
            gamut: gamut,
            transfer: transfer,
            scalePercent: scalePercent,
            hiDPIEnabled: hiDPIEnabled,
            currentEDRHeadroom: currentEDRHeadroom,
            potentialEDRHeadroom: potentialEDRHeadroom,
            currentPeakLuminanceNits: peakLuminanceNits(for: currentEDRHeadroom),
            potentialPeakLuminanceNits: peakLuminanceNits(for: potentialEDRHeadroom)
        )
        #else
        return .init(
            gamut: .sRGB,
            transfer: hdrEnabled ? .pq : .sdr,
            scalePercent: scalePercent,
            hiDPIEnabled: hiDPIEnabled
        )
        #endif
    }

    #if os(macOS)
    @MainActor
    private static func currentMacScreen() -> NSScreen? {
        NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
    }

    private static func gamut(for colorSpace: CGColorSpace?) -> ShadowClientApolloClientDisplayGamut {
        switch colorSpace?.name {
        case CGColorSpace.displayP3:
            return .displayP3
        case CGColorSpace.itur_2020, CGColorSpace.itur_2100_PQ, CGColorSpace.itur_2100_HLG:
            return .rec2020
        default:
            return .sRGB
        }
    }

    private static func currentEDRHeadroom(for screen: NSScreen?) -> Float {
        Float(max(screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0, 1.0))
    }

    private static func potentialEDRHeadroom(for screen: NSScreen?) -> Float {
        Float(max(screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1.0, 1.0))
    }
    #elseif os(iOS) || os(tvOS)
    @MainActor
    private static func currentUIKitScreen() -> UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .screen
    }

    private static func gamut(for displayGamut: UIDisplayGamut) -> ShadowClientApolloClientDisplayGamut {
        switch displayGamut {
        case .P3:
            return .displayP3
        default:
            return .sRGB
        }
    }
    #endif

    static func macTransferContract(
        for colorSpace: CGColorSpace?,
        hdrEnabled: Bool
    ) -> ShadowClientApolloClientDisplayTransfer {
        guard hdrEnabled else {
            return .sdr
        }
        switch colorSpace?.name {
        case CGColorSpace.itur_2100_HLG, CGColorSpace.displayP3_HLG:
            return .hlg
        case CGColorSpace.itur_2100_PQ, CGColorSpace.displayP3_PQ:
            return .pq
        default:
            // macOS can composite EDR highlights over an SDR desktop without the
            // active screen color space becoming PQ. Advertising PQ here makes
            // Apollo treat a Display P3 desktop like a full PQ target.
            return .sdr
        }
    }

    private static func peakLuminanceNits(for headroom: Float) -> Int {
        Int((max(headroom, 1.0) * 100.0).rounded())
    }
}
