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
        guard let screen = currentMacScreen() else {
            return false
        }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
        #elseif os(iOS) || os(tvOS)
        guard #available(iOS 16.0, tvOS 16.0, *) else {
            return false
        }
        let screen = currentUIKitScreen() ?? UIScreen.main
        return screen.potentialEDRHeadroom > 1.0
        #else
        return false
        #endif
    }

    #if os(macOS)
    @MainActor
    private static func currentMacScreen() -> NSScreen? {
        NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
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
    #endif
}
