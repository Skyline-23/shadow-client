import Foundation

enum ShadowClientApolloPermission: CaseIterable, Sendable {
    case listApps
    case viewStreams
    case launchApps
    case keyboardInput
    case mouseInput
    case controllerInput
    case clipboardRead
    case clipboardWrite
    case serverCommand

    var label: String {
        switch self {
        case .listApps: return "List Apps"
        case .viewStreams: return "View Streams"
        case .launchApps: return "Launch Apps"
        case .keyboardInput: return "Keyboard Input"
        case .mouseInput: return "Mouse Input"
        case .controllerInput: return "Controller Input"
        case .clipboardRead: return "Clipboard Read"
        case .clipboardWrite: return "Clipboard Write"
        case .serverCommand: return "Server Command"
        }
    }

    var bit: UInt32 {
        switch self {
        case .controllerInput: return 0x00000100
        case .mouseInput: return 0x00000800
        case .keyboardInput: return 0x00001000
        case .clipboardWrite: return 0x00010000
        case .clipboardRead: return 0x00020000
        case .serverCommand: return 0x00100000
        case .listApps: return 0x01000000
        case .viewStreams: return 0x02000000
        case .launchApps: return 0x04000000
        }
    }

    static func contains(_ permission: ShadowClientApolloPermission, in rawValue: UInt32) -> Bool {
        rawValue & permission.bit != 0
    }

    static func updating(
        _ permission: ShadowClientApolloPermission,
        enabled: Bool,
        in rawValue: UInt32
    ) -> UInt32 {
        if enabled {
            return rawValue | permission.bit
        }
        return rawValue & ~permission.bit
    }

    static func summary(for rawValue: UInt32) -> String {
        let enabled = allCases
            .filter { contains($0, in: rawValue) }
            .map(\.label)
        return enabled.isEmpty ? "Permissions: none" : "Permissions: " + enabled.joined(separator: ", ")
    }
}
