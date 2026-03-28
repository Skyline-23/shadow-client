import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Lumen admin client parser returns the current paired client profile")
func lumenAdminClientParserReturnsCurrentClientProfile() throws {
    let data = Data(
        """
        {
          "status": true,
          "named_certs": [
            {
              "name": "Other Device",
              "uuid": "OTHER-UUID",
              "display_mode": "",
              "perm": 65535,
              "always_use_virtual_display": false,
              "connected": false
            },
            {
              "name": "Current Device",
              "uuid": "CURRENT-UUID",
              "display_mode": "2560x1440x120",
              "perm": 65535,
              "always_use_virtual_display": true,
              "connected": true
            }
          ]
        }
        """.utf8
    )

    let profile = try NativeShadowClientLumenAdminClient.parseCurrentClientProfile(
        data: data,
        currentClientUUID: "CURRENT-UUID"
    )

    #expect(
        profile == .init(
            name: "Current Device",
            uuid: "CURRENT-UUID",
            displayModeOverride: "2560x1440x120",
            permissions: 65535,
            allowClientCommands: true,
            alwaysUseVirtualDisplay: true,
            connected: true
        )
    )
}

@Test("Lumen admin client parser returns nil when the current client is missing")
func lumenAdminClientParserReturnsNilWhenCurrentClientIsMissing() throws {
    let data = Data(
        """
        {
          "status": true,
          "named_certs": [
            {
              "name": "Other Device",
              "uuid": "OTHER-UUID",
              "display_mode": "",
              "perm": 65535,
              "always_use_virtual_display": false,
              "connected": false
            }
          ]
        }
        """.utf8
    )

    let profile = try NativeShadowClientLumenAdminClient.parseCurrentClientProfile(
        data: data,
        currentClientUUID: "CURRENT-UUID"
    )

    #expect(profile == nil)
}
