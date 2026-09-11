// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OhNewsKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "OhNewsKit", targets: ["OhNewsKit"])
    ],
    targets: [
        .target(name: "OhNewsKit"),
        .testTarget(
            name: "OhNewsKitTests",
            dependencies: ["OhNewsKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
