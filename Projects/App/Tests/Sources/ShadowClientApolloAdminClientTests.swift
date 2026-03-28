import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Apollo admin client parser returns the current paired client profile")
func apolloAdminClientParserReturnsCurrentClientProfile() throws {
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

    let profile = try NativeShadowClientApolloAdminClient.parseCurrentClientProfile(
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

@Test("Apollo admin client parser returns nil when the current client is missing")
func apolloAdminClientParserReturnsNilWhenCurrentClientIsMissing() throws {
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

    let profile = try NativeShadowClientApolloAdminClient.parseCurrentClientProfile(
        data: data,
        currentClientUUID: "CURRENT-UUID"
    )

    #expect(profile == nil)
}
