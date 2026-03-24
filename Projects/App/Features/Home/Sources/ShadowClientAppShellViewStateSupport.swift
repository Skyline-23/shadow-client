import Foundation
import CoreGraphics
import SwiftUI

struct ShadowClientHostSpotlightState {
    var hostID: String?
    var sourceFrame: CGRect = .zero
    var animationProgress = 0.0
    var isCardSettled = false
    var task: Task<Void, Never>?
}

struct ShadowClientManualHostEntryState {
    var isPresented = false
    var hostDraft = ""
    var portDraft = ""
}

extension ShadowClientAppShellView {
    var spotlightedHostID: String? {
        get { hostSpotlightState.hostID }
        nonmutating set { hostSpotlightState.hostID = newValue }
    }

    var spotlightedHostSourceFrame: CGRect {
        get { hostSpotlightState.sourceFrame }
        nonmutating set { hostSpotlightState.sourceFrame = newValue }
    }

    var spotlightAnimationProgress: Double {
        get { hostSpotlightState.animationProgress }
        nonmutating set { hostSpotlightState.animationProgress = newValue }
    }

    var spotlightCardSettled: Bool {
        get { hostSpotlightState.isCardSettled }
        nonmutating set { hostSpotlightState.isCardSettled = newValue }
    }

    var hostSpotlightTask: Task<Void, Never>? {
        get { hostSpotlightState.task }
        nonmutating set { hostSpotlightState.task = newValue }
    }

    var isShowingManualHostEntry: Bool {
        get { manualHostEntryState.isPresented }
        nonmutating set { manualHostEntryState.isPresented = newValue }
    }

    var manualHostDraft: String {
        get { manualHostEntryState.hostDraft }
        nonmutating set { manualHostEntryState.hostDraft = newValue }
    }

    var manualHostPortDraft: String {
        get { manualHostEntryState.portDraft }
        nonmutating set { manualHostEntryState.portDraft = newValue }
    }

    var manualHostDraftBinding: Binding<String> {
        Binding(
            get: { manualHostDraft },
            set: { manualHostDraft = $0 }
        )
    }

    var manualHostPortDraftBinding: Binding<String> {
        Binding(
            get: { manualHostPortDraft },
            set: { manualHostPortDraft = $0 }
        )
    }
}
