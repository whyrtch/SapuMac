// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SapuMac",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SapuCore", path: "Sources/SapuCore"),
        .executableTarget(name: "SapuMac", dependencies: ["SapuCore"], path: "Sources/SapuMac"),
        .testTarget(name: "SapuCoreTests", dependencies: ["SapuCore"], path: "Tests/SapuCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
