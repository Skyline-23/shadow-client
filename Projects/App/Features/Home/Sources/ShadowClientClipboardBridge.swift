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

    @MainActor
    static func setString(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #elseif os(iOS) || os(tvOS)
        UIPasteboard.general.string = value
        #endif
    }
}

public protocol ShadowClientClipboardClient: Sendable {
    func currentString() async -> String?
    func setString(_ value: String) async
}

public struct NativeShadowClientClipboardClient: ShadowClientClipboardClient {
    public init() {}

    public func currentString() async -> String? {
        await MainActor.run {
            ShadowClientClipboardBridge.currentString()
        }
    }

    public func setString(_ value: String) async {
        await MainActor.run {
            ShadowClientClipboardBridge.setString(value)
        }
    }
}
