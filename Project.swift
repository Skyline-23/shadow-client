import ProjectDescription

let defaultDevelopmentTeam = "Q23JLSJCCV"

let signableTargetSettings: Settings = .settings(
    base: [:]
        .automaticCodeSigning(devTeam: defaultDevelopmentTeam)
        .codeSignIdentityAppleDevelopment()
)

let project = Project(
    name: "shadow-client",
    targets: [
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
            bundleId: "com.skyline23.shadowClient",
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
                "Projects/App/iOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientNativeAudioDecoding"),
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ],
            settings: signableTargetSettings
        ),
        .target(
            name: "ShadowClientmacOSApp",
            destinations: .macOS,
            product: .app,
            bundleId: "com.skyline23.shadowClient.macos",
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
                "Projects/App/macOS/Sources",
            ],
            dependencies: [
                .target(name: "ShadowClientFeatureHome"),
                .target(name: "ShadowClientNativeAudioDecoding"),
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ],
            settings: signableTargetSettings
        ),
        .target(
            name: "ShadowClienttvOSApp",
            destinations: .tvOS,
            product: .app,
            bundleId: "com.skyline23.shadowClient.tvos",
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
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
            ],
            settings: signableTargetSettings
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
                .target(name: "ShadowClientNativeAudioDecoding"),
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
                .target(name: "ShadowClientNativeAudioDecoding"),
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
