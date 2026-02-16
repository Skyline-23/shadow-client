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
            infoPlist: .default,
            buildableFolders: [
                "Projects/App/Features/Home/Sources",
            ],
            dependencies: [
                .external(name: "ShadowClientStreaming"),
                .external(name: "ShadowClientUI"),
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
            infoPlist: .default,
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
                .target(name: "ShadowClientiOSApp"),
                .target(name: "ShadowClientFeatureHome"),
                .external(name: "Testing"),
            ]
        ),
    ]
)
