import Foundation

struct ShadowClientSettingsCopyKit {
    static func autoBitrateFootnote() -> String {
        "Estimated from resolution, frame rate, codec, HDR, and YUV444."
    }

    static func hdrUnavailableFootnote() -> String {
        "HDR requires a real HDR/EDR display on this device."
    }

    static func mobileAudioRouteFootnote() -> String {
        "On iPhone and iPad, your selection is the ceiling. The active audio route can still cap playback lower, and built-in speakers or most headphones stay stereo."
    }

    static func clientPlaybackUnavailableFootnote() -> String {
        "Client audio playback is not available yet. Audio is currently routed to the host device."
    }
}
