// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "C4M",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        .library(name: "C4M", targets: ["C4M"]),
    ],
    targets: [
        .target(name: "C4M"),
        .testTarget(name: "C4MTests", dependencies: ["C4M"]),
    ]
)
