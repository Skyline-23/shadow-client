// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShadowClientModules",
    platforms: [
        .iOS(.v17),
        .tvOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ShadowClientCore", targets: ["ShadowClientCore"]),
        .library(name: "ShadowClientStreaming", targets: ["ShadowClientStreaming"]),
        .library(name: "ShadowClientInput", targets: ["ShadowClientInput"]),
        .library(name: "ShadowClientUI", targets: ["ShadowClientUI"]),
        .library(name: "ShadowClientFeatureHome", targets: ["ShadowClientFeatureHome"]),
    ],
    targets: [
        .target(
            name: "ShadowClientCore",
            path: "ShadowClientCore/Sources"
        ),
        .target(
            name: "ShadowClientStreaming",
            dependencies: ["ShadowClientCore"],
            path: "ShadowClientStreaming/Sources"
        ),
        .target(
            name: "ShadowClientInput",
            dependencies: ["ShadowClientCore"],
            path: "ShadowClientInput/Sources"
        ),
        .target(
            name: "ShadowClientUI",
            dependencies: ["ShadowClientCore", "ShadowClientStreaming", "ShadowClientInput"],
            path: "ShadowClientUI/Sources"
        ),
        .target(
            name: "ShadowClientFeatureHome",
            dependencies: ["ShadowClientCore", "ShadowClientStreaming", "ShadowClientInput", "ShadowClientUI"],
            path: "ShadowClientFeatureHome/Sources"
        ),
        .testTarget(
            name: "ShadowClientCoreTests",
            dependencies: ["ShadowClientCore"],
            path: "ShadowClientCore/Tests"
        ),
        .testTarget(
            name: "ShadowClientStreamingTests",
            dependencies: ["ShadowClientStreaming"],
            path: "ShadowClientStreaming/Tests"
        ),
        .testTarget(
            name: "ShadowClientInputTests",
            dependencies: ["ShadowClientInput"],
            path: "ShadowClientInput/Tests"
        ),
        .testTarget(
            name: "ShadowClientUITests",
            dependencies: ["ShadowClientUI"],
            path: "ShadowClientUI/Tests"
        ),
        .testTarget(
            name: "ShadowClientFeatureHomeTests",
            dependencies: ["ShadowClientFeatureHome"],
            path: "ShadowClientFeatureHome/Tests"
        ),
    ]
)
