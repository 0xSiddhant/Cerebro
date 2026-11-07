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
    ],
    dependencies: [
        // Broad on purpose: the host app's generated `.pb.swift` files pin their own version.
        .package(url: "https://github.com/apple/swift-protobuf.git", "1.27.0"..<"2.0.0"),
    ],
    targets: [
        .target(
            name: "CerebroCore",
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
        .testTarget(
            name: "CerebroCoreTests",
            dependencies: ["CerebroCore"],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CerebroProtoTests",
            dependencies: ["CerebroProto"],
            swiftSettings: swiftSettings
        ),
    ]
)
