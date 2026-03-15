#if os(macOS)
import AppKit
import SwiftUI

struct ShadowClientDisplayMetricsObserver: NSViewRepresentable {
    let onMetricsChanged: @MainActor (ShadowClientDisplayMetricsState) -> Void

    func makeNSView(context: Context) -> ShadowClientDisplayMetricsNSView {
        let view = ShadowClientDisplayMetricsNSView()
        view.onMetricsChanged = onMetricsChanged
        return view
    }

    func updateNSView(_ nsView: ShadowClientDisplayMetricsNSView, context: Context) {
        nsView.onMetricsChanged = onMetricsChanged
        nsView.publishMetricsIfNeeded()
    }
}

@MainActor
final class ShadowClientDisplayMetricsNSView: NSView {
    var onMetricsChanged: (@MainActor (ShadowClientDisplayMetricsState) -> Void)?

    private weak var observedWindow: NSWindow?
    private var lastPublishedState: ShadowClientDisplayMetricsState?

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

        let pixelSize: CGSize?
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
           let mode = CGDisplayCopyDisplayMode(CGDirectDisplayID(screenNumber.uint32Value)) {
            pixelSize = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        } else {
            pixelSize = nil
        }

        let nextState = ShadowClientDisplayMetricsState(
            scale: screen.backingScaleFactor,
            pixelSize: pixelSize,
            logicalSize: window?.contentLayoutRect.size ?? screen.frame.size
        )
        guard lastPublishedState != nextState else {
            return
        }
        lastPublishedState = nextState

        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            self.onMetricsChanged?(nextState)
        }
    }
}
#endif
