import CoreGraphics
import Foundation

enum ShadowClientLumenClientDisplayTransferContract {
    enum Environment {
        case compositedUIKit
        case colorManagedDesktop(CGColorSpace?)
    }

    static func resolve(
        hdrEnabled: Bool,
        environment: Environment
    ) -> ShadowClientLumenClientDisplayTransfer {
        guard hdrEnabled else {
            return .sdr
        }

        switch environment {
        case .compositedUIKit:
            // Lumen's current Shadow HDR transport negotiates an explicit HDR
            // transfer function for sink capability instead of inferring it from
            // the UI composition surface.
            return .pq
        case let .colorManagedDesktop(colorSpace):
            switch colorSpace?.name {
            case CGColorSpace.itur_2100_HLG, CGColorSpace.displayP3_HLG:
                return .hlg
            case CGColorSpace.itur_2100_PQ, CGColorSpace.displayP3_PQ:
                return .pq
            default:
                // Lumen's macOS bridge currently defaults HDR transport to PQ
                // unless the sink explicitly advertises HLG.
                return .pq
            }
        }
    }
}
