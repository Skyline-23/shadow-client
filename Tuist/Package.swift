// swift-tools-version: 6.0
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [
            "SwiftOpus": .framework,
        ],
        baseSettings: .settings(
            base: [
                "OTHER_LIBTOOLFLAGS": "$(inherited) -no_warning_for_no_symbols",
            ]
        )
    )
#endif

let package = Package(
    name: "shadow-client",
    dependencies: [
        .package(path: "../Modules"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.0.3"),
        .package(url: "https://github.com/Skyline-23/SwiftOpus.git", exact: "0.3.0"),
    ]
)
