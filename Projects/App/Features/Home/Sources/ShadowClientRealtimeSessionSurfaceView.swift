import SwiftUI

#if os(iOS) || os(tvOS)
import UIKit

private struct ShadowClientRealtimeSessionSurfaceRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = true
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.backgroundColor = .black
    }
}
#elseif os(macOS)
import AppKit

private struct ShadowClientRealtimeSessionSurfaceRepresentable: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.wantsLayer = true
        nsView.layer?.backgroundColor = NSColor.black.cgColor
    }
}
#endif

public struct ShadowClientRealtimeSessionSurfaceView: View {
    public init() {}

    public var body: some View {
        ShadowClientRealtimeSessionSurfaceRepresentable()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("remote-desktop-native-surface")
            .accessibilityLabel("Remote desktop native surface")
    }
}
