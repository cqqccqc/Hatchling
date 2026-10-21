// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HatchlingKit",
    platforms: [
        .watchOS(.v11),
        .macOS(.v15),   // 为 Baker（构建期烘焙）预留
    ],
    products: [
        .library(name: "HatchlingKit", targets: ["HatchlingKit"]),
    ],
    targets: [
        .target(
            name: "HatchlingKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "HatchlingKitTests",
            dependencies: ["HatchlingKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
