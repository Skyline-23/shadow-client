// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import struct ProjectDescription.PackageSettings

    let packageSettings = PackageSettings(
        productTypes: [
            "SwiftOpus": .framework,
        ]
    )
#endif

let package = Package(
    name: "shadow-client",
    dependencies: [
        .package(path: "../Modules"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.0.3"),
        .package(
            url: "git@github.com:Skyline-23/SwiftOpus.git",
            .upToNextMinor(from: "0.1.0")
        ),
    ]
)
