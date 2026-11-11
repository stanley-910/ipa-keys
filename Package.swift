// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ipa-keys",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ipa-keys", targets: ["ipa-keys"]),
    ],
    targets: [
        // Config parsing, cycling and name matching: no AppKit, so it is testable.
        .target(
            name: "IPAKeysCore",
            path: "Sources/IPAKeysCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ipa-keys",
            dependencies: ["IPAKeysCore"],
            path: "Sources/ipa-keys",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
            ]
        ),
        .testTarget(
            name: "IPAKeysCoreTests",
            dependencies: ["IPAKeysCore"],
            path: "Tests/IPAKeysCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
