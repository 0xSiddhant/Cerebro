// swift-tools-version: 5.9

import PackageDescription

// `StrictConcurrency` is on through a feature flag rather than `unsafeFlags`,
// because a package with unsafe flags can't be used as a versioned dependency.
let swiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

let package = Package(
    name: "Cerebro",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "Cerebro", targets: ["Cerebro"]),
        .library(name: "CerebroProto", targets: ["CerebroProto"]),
        .plugin(name: "CerebroProtoPlugin", targets: ["CerebroProtoPlugin"]),
    ],
    dependencies: [
        // Broad on purpose: the host app's generated `.pb.swift` files pin their own version.
        .package(url: "https://github.com/apple/swift-protobuf.git", "1.27.0"..<"2.0.0"),
    ],
    targets: [
        // The privacy manifest is shipped, never read. `.process` is the form Apple's documentation uses.
        .target(
            name: "CerebroCore",
            resources: [.process("PrivacyInfo.xcprivacy")],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "Cerebro",
            dependencies: ["CerebroCore"],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "CerebroProto",
            dependencies: [
                "CerebroCore",
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ],
            swiftSettings: swiftSettings
        ),
        // The logic is a library because an executable can't be linked into tests on iOS.
        .target(
            name: "CerebroProtoGeneratorCore",
            swiftSettings: swiftSettings
        ),
        .executableTarget(
            name: "CerebroProtoGenerator",
            dependencies: ["CerebroProtoGeneratorCore"],
            swiftSettings: swiftSettings
        ),
        .plugin(
            name: "CerebroProtoPlugin",
            capability: .buildTool(),
            dependencies: ["CerebroProtoGenerator"]
        ),
        .testTarget(
            name: "CerebroCoreTests",
            dependencies: ["CerebroCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CerebroTests",
            dependencies: ["Cerebro"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CerebroProtoTests",
            dependencies: ["CerebroProto"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CerebroProtoGeneratorTests",
            dependencies: ["CerebroProtoGeneratorCore"],
            swiftSettings: swiftSettings
        ),
    ]
)
