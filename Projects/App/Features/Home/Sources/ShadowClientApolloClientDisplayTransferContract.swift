import CoreGraphics
import Foundation

enum ShadowClientApolloClientDisplayTransferContract {
    enum Environment {
        case compositedUIKit
        case colorManagedDesktop(CGColorSpace?)
    }

    static func resolve(
        hdrEnabled: Bool,
        environment: Environment
    ) -> ShadowClientApolloClientDisplayTransfer {
        guard hdrEnabled else {
            return .sdr
        }

        switch environment {
        case .compositedUIKit:
            // UIKit keeps app content in an SDR-referred desktop/UI composition
            // surface and lets HDR/EDR content extend above that surface.
            return .sdr
        case let .colorManagedDesktop(colorSpace):
            switch colorSpace?.name {
            case CGColorSpace.itur_2100_HLG, CGColorSpace.displayP3_HLG:
                return .hlg
            case CGColorSpace.itur_2100_PQ, CGColorSpace.displayP3_PQ:
                return .pq
            default:
                // macOS can composite EDR highlights over an SDR desktop without
                // the active screen color space becoming PQ.
                return .sdr
            }
        }
    }
}
