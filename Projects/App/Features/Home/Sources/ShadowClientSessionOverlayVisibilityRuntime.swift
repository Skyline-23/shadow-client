import SwiftUI

@MainActor
final class ShadowClientSessionOverlayVisibilityRuntime: ObservableObject {
    @Published private(set) var isVisible = true

    private var isSessionActive = false
    private var latestRenderState: ShadowClientRealtimeSessionSurfaceContext.RenderState = .idle
    private var autoHideTask: Task<Void, Never>?
    private let autoHideDelay: Duration

    init(autoHideDelay: Duration = .seconds(3)) {
        self.autoHideDelay = autoHideDelay
    }

    deinit {
        autoHideTask?.cancel()
    }

    func setSessionActive(_ isActive: Bool) {
        isSessionActive = isActive

        guard isActive else {
            cancelAutoHide()
            isVisible = true
            latestRenderState = .idle
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = true
        }
        scheduleAutoHideIfNeeded()
    }

    func applyRenderState(_ renderState: ShadowClientRealtimeSessionSurfaceContext.RenderState) {
        latestRenderState = renderState

        switch renderState {
        case .rendering:
            scheduleAutoHideIfNeeded()
        case .idle, .connecting, .waitingForFirstFrame, .disconnected, .failed:
            cancelAutoHide()
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible = true
            }
        }
    }

    func registerInteraction() {
        guard isSessionActive else {
            return
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = true
        }
        scheduleAutoHideIfNeeded()
    }

    func toggleByLocalCommand() {
        guard isSessionActive else {
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible.toggle()
        }

        if isVisible {
            scheduleAutoHideIfNeeded()
        } else {
            cancelAutoHide()
        }
    }

    func setVisible(_ visible: Bool) {
        guard isSessionActive else {
            isVisible = visible
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            isVisible = visible
        }

        if visible {
            scheduleAutoHideIfNeeded()
        } else {
            cancelAutoHide()
        }
    }

    private func scheduleAutoHideIfNeeded() {
        cancelAutoHide()

        guard isSessionActive else {
            return
        }

        guard case .rendering = latestRenderState else {
            return
        }

        autoHideTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(for: self.autoHideDelay)
            } catch {
                return
            }

            guard self.isSessionActive else {
                return
            }

            guard case .rendering = self.latestRenderState else {
                return
            }

            withAnimation(.easeInOut(duration: 0.2)) {
                self.isVisible = false
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
