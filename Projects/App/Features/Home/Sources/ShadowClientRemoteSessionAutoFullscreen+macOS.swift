#if os(macOS)
import AppKit
import SwiftUI

struct ShadowClientRemoteSessionAutoFullscreenModifier: ViewModifier {
    let isSessionActive: Bool

    func body(content: Content) -> some View {
        content
            .background(
                ShadowClientRemoteSessionAutoFullscreenBridge(
                    isSessionActive: isSessionActive
                )
                .allowsHitTesting(false)
            )
    }
}

private struct ShadowClientRemoteSessionAutoFullscreenBridge: NSViewRepresentable {
    let isSessionActive: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        context.coordinator.bind(to: view)
        context.coordinator.updateSessionState(isSessionActive)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.bind(to: nsView)
        context.coordinator.updateSessionState(isSessionActive)
    }

    static func dismantleNSView(
        _ nsView: NSView,
        coordinator: Coordinator
    ) {
        coordinator.unbind(from: nsView)
    }

    final class Coordinator {
        private weak var observationView: NSView?
        private weak var window: NSWindow?
        private var enteredFullscreenForSession = false
        private var isSessionActive = false
        private var pendingApplyTask: DispatchWorkItem?

        func bind(to view: NSView) {
            observationView = view
            attachWindowIfNeeded(view.window)
        }

        func unbind(from view: NSView) {
            if observationView === view {
                observationView = nil
            }
            window = nil
            pendingApplyTask?.cancel()
            pendingApplyTask = nil
            enteredFullscreenForSession = false
            isSessionActive = false
        }

        func updateSessionState(_ isActive: Bool) {
            isSessionActive = isActive
            scheduleApply()
        }

        private func attachWindowIfNeeded(_ candidate: NSWindow?) {
            guard let candidate else {
                return
            }
            guard window !== candidate else {
                return
            }
            window = candidate
            scheduleApply()
        }

        private func scheduleApply() {
            pendingApplyTask?.cancel()
            let task = DispatchWorkItem { [weak self] in
                self?.apply()
            }
            pendingApplyTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: task)
        }

        private func apply() {
            if window == nil {
                attachWindowIfNeeded(observationView?.window)
            }

            guard let window else {
                return
            }

            let isFullscreen = window.styleMask.contains(.fullScreen)

            if isSessionActive {
                guard !isFullscreen else {
                    return
                }
                guard !enteredFullscreenForSession else {
                    return
                }
                enteredFullscreenForSession = true
                window.toggleFullScreen(nil)
                return
            }

            guard enteredFullscreenForSession else {
                return
            }

            guard isFullscreen else {
                enteredFullscreenForSession = false
                return
            }

            enteredFullscreenForSession = false
            window.toggleFullScreen(nil)
        }
    }
}
#endif
