import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS) || os(tvOS)
import UIKit
#endif

enum ShadowClientClipboardBridge {
    @MainActor
    static func hasStringContents() -> Bool {
        #if os(macOS)
        !(NSPasteboard.general.string(forType: .string) ?? "").isEmpty
        #elseif os(iOS) || os(tvOS)
        UIPasteboard.general.hasStrings
        #else
        false
        #endif
    }

    @MainActor
    static func currentString() -> String? {
        let text: String?
        #if os(macOS)
        text = NSPasteboard.general.string(forType: .string)
        #elseif os(iOS) || os(tvOS)
        text = UIPasteboard.general.string
        #else
        text = nil
        #endif

        guard let trimmed = text?
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }
}
