// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OnlyMacsApp",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "OnlyMacsCore", targets: ["OnlyMacsCore"]),
        .executable(name: "OnlyMacsApp", targets: ["OnlyMacsApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.8.0"),
    ],
    targets: [
        .target(
            name: "OnlyMacsCore",
            path: "Sources/OnlyMacsCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "OnlyMacsApp",
            dependencies: [
                "OnlyMacsCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/OnlyMacsApp"
        ),
        .testTarget(
            name: "OnlyMacsCoreTests",
            dependencies: ["OnlyMacsCore"],
            path: "Tests/OnlyMacsCoreTests"
        ),
        .testTarget(
            name: "OnlyMacsAppTests",
            dependencies: ["OnlyMacsApp"],
            path: "Tests/OnlyMacsAppTests"
        ),
    ]
)
