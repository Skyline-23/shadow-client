import ProjectDescription

let defaultDevelopmentTeam = "Q23JLSJCCV"

let signableTargetBaseSettings: SettingsDictionary = [:]
    .automaticCodeSigning(devTeam: defaultDevelopmentTeam)
    .codeSignIdentityAppleDevelopment()

let signableTargetSettings: Settings = .settings(
    base: signableTargetBaseSettings
)

let layeredAppIconResources: ResourceFileElements = [
    .folderReference(path: "shadow.icon"),
]

let layeredAppIconSettings: SettingsDictionary = [
    "ASSETCATALOG_COMPILER_APPICON_NAME": "shadow",
]

let project = Project(
    name: "shadow-client",
    targets: [
        .target(
            name: "ShadowClientFeatureConnection",
            destinations: [.iPhone, .iPad, .mac, .appleTv],
            product: .framework,
            bundleId: "com.skyline23.shadowClient.feature.connection",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0", tvOS: "17.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Features/Connection/Sources",
            ],
            dependencies: [
                .external(name: "ShadowClientStreaming"),
            ]
        ),
        .target(
            name: "ShadowClientFeatureSession",
            destinations: [.iPhone, .iPad, .mac, .appleTv],
            product: .framework,
            bundleId: "com.skyline23.shadowClient.feature.session",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0", tvOS: "17.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Features/Session/Sources",
            ]
        ),
        .target(
            name: "ShadowUIFoundation",
            destinations: [.iPhone, .iPad, .mac, .appleTv],
            product: .framework,
            bundleId: "com.skyline23.shadowClient.ui.foundation",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0", tvOS: "17.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/UI/Foundation/Sources",
            ]
        ),
        .target(
            name: "ShadowClientFeatureHome",
            destinations: [.iPhone, .iPad, .mac, .appleTv],
            product: .framework,
            bundleId: "com.skyline23.shadowClient.feature.home",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0", tvOS: "17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSExceptionDomains": [
                            "stream-host.example.invalid": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true,
                                "NSTemporaryExceptionAllowsInsecureHTTPLoads": true,
                            ],
                        ],
                    ],
                ]
            ),
            buildableFolders: [
                "Projects/App/Features/Home/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureConnection"),
                .target(name: "ShadowClientFeatureSession"),
                .target(name: "ShadowUIFoundation"),
                .external(name: "ShadowClientInput"),
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ]
        ),
        .target(
            name: "ShadowClientNativeAudioDecoding",
            destinations: [.iPhone, .iPad, .mac, .appleTv],
            product: .framework,
            bundleId: "com.skyline23.shadowClient.native-audio-decoding",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0", tvOS: "17.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Features/NativeAudio/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .external(name: "SwiftOpus"),
            ]
        ),
        .target(
            name: "ShadowClientiOSApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.skyline23.shadowClient.ios",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Shadow",
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSLocalNetworkUsageDescription": "shadow-client discovers streaming hosts on your local network.",
                    "NSBonjourServices": [
                        "_shadow._tcp",
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSExceptionDomains": [
                            "stream-host.example.invalid": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true,
                                "NSTemporaryExceptionAllowsInsecureHTTPLoads": true,
                            ],
                        ],
                    ],
                ]
            ),
            resources: layeredAppIconResources,
            buildableFolders: [
                "Projects/App/iOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientNativeAudioDecoding"),
            ],
            settings: .settings(
                base: signableTargetBaseSettings.merging(
                    [
                        "INFOPLIST_KEY_CFBundleDisplayName": "Shadow",
                    ].merging(layeredAppIconSettings, uniquingKeysWith: { _, new in new }),
                    uniquingKeysWith: { _, new in new }
                )
            )
        ),
        .target(
            name: "ShadowClientmacOSApp",
            destinations: .macOS,
            product: .app,
            bundleId: "com.skyline23.shadowClient.macos",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Shadow",
                    "NSLocalNetworkUsageDescription": "shadow-client discovers streaming hosts on your local network.",
                    "NSBonjourServices": [
                        "_shadow._tcp",
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSExceptionDomains": [
                            "stream-host.example.invalid": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true,
                                "NSTemporaryExceptionAllowsInsecureHTTPLoads": true,
                            ],
                        ],
                    ],
                ]
            ),
            resources: layeredAppIconResources,
            buildableFolders: [
                "Projects/App/macOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientNativeAudioDecoding"),
            ],
            settings: .settings(
                base: signableTargetBaseSettings.merging(
                    [
                        "INFOPLIST_KEY_CFBundleDisplayName": "Shadow",
                    ].merging(layeredAppIconSettings, uniquingKeysWith: { _, new in new }),
                    uniquingKeysWith: { _, new in new }
                )
            )
        ),
        .target(
            name: "ShadowClienttvOSApp",
            destinations: .tvOS,
            product: .app,
            bundleId: "com.skyline23.shadowClient.tvos",
            deploymentTargets: .tvOS("17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "CFBundleDisplayName": "Shadow",
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSLocalNetworkUsageDescription": "shadow-client discovers streaming hosts on your local network.",
                    "NSBonjourServices": [
                        "_shadow._tcp",
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSExceptionDomains": [
                            "stream-host.example.invalid": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true,
                                "NSTemporaryExceptionAllowsInsecureHTTPLoads": true,
                            ],
                        ],
                    ],
                ]
            ),
            buildableFolders: [
                "Projects/App/tvOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientNativeAudioDecoding"),
            ],
            settings: .settings(
                base: signableTargetBaseSettings.merging(
                    ["INFOPLIST_KEY_CFBundleDisplayName": "Shadow"],
                    uniquingKeysWith: { _, new in new }
                )
            )
        ),
        .target(
            name: "ShadowClientTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.skyline23.shadowClient.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Tests/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientFeatureConnection"),
                .target(name: "ShadowClientFeatureSession"),
                .target(name: "ShadowClientNativeAudioDecoding"),
                .target(name: "ShadowUIFoundation"),
                .external(name: "Testing"),
            ],
            settings: signableTargetSettings
        ),
        .target(
            name: "ShadowClientmacOSTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.skyline23.shadowClient.macos.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Tests/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientFeatureConnection"),
                .target(name: "ShadowClientFeatureSession"),
                .target(name: "ShadowClientNativeAudioDecoding"),
                .target(name: "ShadowUIFoundation"),
                .external(name: "Testing"),
            ],
            settings: signableTargetSettings
        ),
        .target(
            name: "ShadowClientmacOSUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.skyline23.shadowClient.macos.uitests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/macOSUITests/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientmacOSApp"),
            ],
            settings: signableTargetSettings
        ),
    ]
)
