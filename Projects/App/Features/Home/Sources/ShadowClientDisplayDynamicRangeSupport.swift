import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

enum ShadowClientDisplayDynamicRangeSupport {
    @MainActor
    static func currentDisplaySupportsHDR() -> Bool {
        #if os(macOS)
        guard #available(macOS 10.15, *) else {
            return false
        }
        return NSScreen.screens.contains { screen in
            screen.maximumExtendedDynamicRangeColorComponentValue > 1.01
        }
        #elseif os(iOS) || os(tvOS)
        guard #available(iOS 16.0, tvOS 16.0, *) else {
            return false
        }
        let screens = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .map(\.screen)
        return screens.contains { screen in
            screen.currentEDRHeadroom > 1.01
        }
        #else
        return false
        #endif
    }
}
