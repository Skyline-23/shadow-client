import SwiftUI

#if os(macOS)
import AppKit

struct ShadowClientRealtimeSessionSurfaceRepresentable: NSViewRepresentable {
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
