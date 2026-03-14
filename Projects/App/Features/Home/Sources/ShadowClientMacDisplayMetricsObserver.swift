#if os(macOS)
import AppKit
import SwiftUI

struct ShadowClientMacDisplayMetricsObserver: NSViewRepresentable {
    let onMetricsChanged: @MainActor (_ scale: CGFloat, _ pixelSize: CGSize?) -> Void

    func makeNSView(context: Context) -> ShadowClientMacDisplayMetricsNSView {
        let view = ShadowClientMacDisplayMetricsNSView()
        view.onMetricsChanged = onMetricsChanged
        return view
    }

    func updateNSView(_ nsView: ShadowClientMacDisplayMetricsNSView, context: Context) {
        nsView.onMetricsChanged = onMetricsChanged
        nsView.publishMetricsIfNeeded()
    }
}

@MainActor
final class ShadowClientMacDisplayMetricsNSView: NSView {
    var onMetricsChanged: (@MainActor (_ scale: CGFloat, _ pixelSize: CGSize?) -> Void)?

    private weak var observedWindow: NSWindow?
    private var lastPublishedScale: CGFloat?
    private var lastPublishedPixelSize: CGSize?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if observedWindow !== window {
            NotificationCenter.default.removeObserver(self)
            observedWindow = window

            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowScreenDidChange(_:)),
                    name: NSWindow.didChangeScreenNotification,
                    object: window
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowBackingPropertiesDidChange(_:)),
                    name: NSWindow.didChangeBackingPropertiesNotification,
                    object: window
                )
            }
        }

        publishMetricsIfNeeded()
    }

    override func layout() {
        super.layout()
        publishMetricsIfNeeded()
    }

    @objc
    private func windowScreenDidChange(_ notification: Notification) {
        _ = notification
        publishMetricsIfNeeded()
    }

    @objc
    private func windowBackingPropertiesDidChange(_ notification: Notification) {
        _ = notification
        publishMetricsIfNeeded()
    }

    func publishMetricsIfNeeded() {
        guard let screen = window?.screen else {
            return
        }

        let scale = screen.backingScaleFactor
        let pixelSize: CGSize?
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(screenNumber.uint32Value)) {
            pixelSize = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        } else {
            pixelSize = nil
        }

        guard lastPublishedScale != scale || lastPublishedPixelSize != pixelSize else {
            return
        }

        lastPublishedScale = scale
        lastPublishedPixelSize = pixelSize

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.onMetricsChanged?(scale, pixelSize)
        }
    }
}
#endif
