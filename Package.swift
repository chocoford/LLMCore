// swift-tools-version: 6.1.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "LLMCore",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "LLMCore",
            targets: ["LLMCore"]
        ),
    ],
    dependencies: [
        // OPEN AI
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "LLMCore",
            dependencies: [
                .product(name: "OpenAI", package: "OpenAI"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "AnyCodable", package: "AnyCodable"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "LLMCoreTests",
            dependencies: ["LLMCore"]
        ),
    ]
)
