#if !os(macOS)
import SwiftUI
import UIKit

struct ShadowClientDisplayMetricsObserver: UIViewRepresentable {
    let onMetricsChanged: @MainActor (ShadowClientDisplayMetricsState) -> Void

    func makeUIView(context: Context) -> ShadowClientDisplayMetricsUIView {
        let view = ShadowClientDisplayMetricsUIView()
        view.onMetricsChanged = onMetricsChanged
        return view
    }

    func updateUIView(_ uiView: ShadowClientDisplayMetricsUIView, context: Context) {
        uiView.onMetricsChanged = onMetricsChanged
        uiView.publishMetricsIfNeeded()
    }
}

@MainActor
final class ShadowClientDisplayMetricsUIView: UIView {
    var onMetricsChanged: (@MainActor (ShadowClientDisplayMetricsState) -> Void)?

    private weak var observedWindow: UIWindow?
    private var lastPublishedState: ShadowClientDisplayMetricsState?

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if observedWindow !== window {
            NotificationCenter.default.removeObserver(self)
            observedWindow = window

            if let window {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidBecomeKey(_:)),
                    name: UIWindow.didBecomeKeyNotification,
                    object: window
                )
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidBecomeVisible(_:)),
                    name: UIWindow.didBecomeVisibleNotification,
                    object: window
                )
            }
        }

        publishMetricsIfNeeded()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        publishMetricsIfNeeded()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        publishMetricsIfNeeded()
    }

    @objc
    private func windowDidBecomeKey(_ notification: Notification) {
        _ = notification
        publishMetricsIfNeeded()
    }

    @objc
    private func windowDidBecomeVisible(_ notification: Notification) {
        _ = notification
        publishMetricsIfNeeded()
    }

    func publishMetricsIfNeeded() {
        let activeWindow = window
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        let screen = activeWindow?.screen ?? keyWindow?.screen ?? UIScreen.main
        let sourceWindow = activeWindow ?? keyWindow

        let logicalSize = sourceWindow?.bounds.size ?? screen.bounds.size
        let safeAreaInsets = sourceWindow.map { EdgeInsets($0.safeAreaInsets) } ?? .init()
        let nativeWidth = max(screen.nativeBounds.width, 1)
        let nativeHeight = max(screen.nativeBounds.height, 1)
        let boundsWidth = max(screen.bounds.width, 1)
        let boundsHeight = max(screen.bounds.height, 1)
        let effectiveScale = max(
            screen.scale,
            max(nativeWidth / boundsWidth, nativeHeight / boundsHeight)
        )
        let scale = max(1.0, effectiveScale)
        let pixelSize = CGSize(
            width: logicalSize.width * scale,
            height: logicalSize.height * scale
        )
        let nextState = ShadowClientDisplayMetricsState(
            scale: scale,
            pixelSize: pixelSize,
            logicalSize: logicalSize,
            safeAreaInsets: safeAreaInsets
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

private extension EdgeInsets {
    init(_ insets: UIEdgeInsets) {
        self.init(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
    }
}
#endif
