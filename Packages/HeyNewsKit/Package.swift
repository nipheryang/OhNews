// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HeyNewsKit",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "HeyNewsKit", targets: ["HeyNewsKit"])
    ],
    targets: [
        .target(name: "HeyNewsKit"),
        .testTarget(
            name: "HeyNewsKitTests",
            dependencies: ["HeyNewsKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
