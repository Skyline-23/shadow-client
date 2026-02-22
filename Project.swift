import ProjectDescription

let project = Project(
    name: "shadow-client",
    targets: [
        .target(
            name: "ShadowClientFeatureHome",
            destinations: [.iPhone, .iPad, .mac, .appleTv],
            product: .framework,
            bundleId: "com.skyline23.shadow-client.feature.home",
            deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0", tvOS: "17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSAllowsLocalNetworking": true,
                        "NSExceptionDomains": [
                            "wifi.skyline23.com": [
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
                .sdk(name: "AppIntents", type: .framework),
                .external(name: "ShadowClientInput"),
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ]
        ),
        .target(
            name: "ShadowClientNativeAudioDecoding",
            destinations: .macOS,
            product: .framework,
            bundleId: "com.skyline23.shadow-client.native-audio-decoding",
            deploymentTargets: .macOS("14.0"),
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
            bundleId: "com.skyline23.shadow-client",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSLocalNetworkUsageDescription": "shadow-client discovers streaming hosts on your local network.",
                    "NSBonjourServices": [
                        "_nvstream._tcp",
                        "_sunshine._tcp",
                        "_moonlight._tcp",
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSAllowsLocalNetworking": true,
                        "NSExceptionDomains": [
                            "wifi.skyline23.com": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true,
                                "NSTemporaryExceptionAllowsInsecureHTTPLoads": true,
                            ],
                        ],
                    ],
                ]
            ),
            buildableFolders: [
                "Projects/App/iOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ]
        ),
        .target(
            name: "ShadowClientmacOSApp",
            destinations: .macOS,
            product: .app,
            bundleId: "com.skyline23.shadow-client.macos",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .extendingDefault(
                with: [
                    "NSLocalNetworkUsageDescription": "shadow-client discovers streaming hosts on your local network.",
                    "NSBonjourServices": [
                        "_nvstream._tcp",
                        "_sunshine._tcp",
                        "_moonlight._tcp",
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSAllowsLocalNetworking": true,
                        "NSExceptionDomains": [
                            "wifi.skyline23.com": [
                                "NSIncludesSubdomains": true,
                                "NSExceptionAllowsInsecureHTTPLoads": true,
                                "NSTemporaryExceptionAllowsInsecureHTTPLoads": true,
                            ],
                        ],
                    ],
                ]
            ),
            buildableFolders: [
                "Projects/App/macOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ]
        ),
        .target(
            name: "ShadowClienttvOSApp",
            destinations: .tvOS,
            product: .app,
            bundleId: "com.skyline23.shadow-client.tvos",
            deploymentTargets: .tvOS("17.0"),
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchScreen": [
                        "UIColorName": "",
                        "UIImageName": "",
                    ],
                    "NSLocalNetworkUsageDescription": "shadow-client discovers streaming hosts on your local network.",
                    "NSBonjourServices": [
                        "_nvstream._tcp",
                        "_sunshine._tcp",
                        "_moonlight._tcp",
                    ],
                    "NSAppTransportSecurity": [
                        "NSAllowsArbitraryLoads": true,
                        "NSAllowsLocalNetworking": true,
                        "NSExceptionDomains": [
                            "wifi.skyline23.com": [
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
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ]
        ),
        .target(
            name: "ShadowClientTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.skyline23.shadow-client.tests",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Tests/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .sdk(name: "AppIntents", type: .framework),
                .external(name: "Testing"),
            ]
        ),
        .target(
            name: "ShadowClientmacOSTests",
            destinations: .macOS,
            product: .unitTests,
            bundleId: "com.skyline23.shadow-client.macos.tests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Tests/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .sdk(name: "AppIntents", type: .framework),
                .external(name: "Testing"),
            ]
        ),
        .target(
            name: "ShadowClientmacOSUITests",
            destinations: .macOS,
            product: .uiTests,
            bundleId: "com.skyline23.shadow-client.macos.uitests",
            deploymentTargets: .macOS("14.0"),
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/macOSUITests/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientmacOSApp"),
            ]
        ),
    ]
)
