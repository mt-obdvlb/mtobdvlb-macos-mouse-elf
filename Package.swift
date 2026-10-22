// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MouseElf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MouseElf", targets: ["MouseElf"])],
    targets: [
        .target(name: "MouseElfCore"),
        .executableTarget(name: "MouseElf", dependencies: ["MouseElfCore"]),
        .testTarget(name: "MouseElfCoreTests", dependencies: ["MouseElfCore"]),
        .testTarget(name: "MouseElfTests", dependencies: ["MouseElf", "MouseElfCore"]),
    ],
    swiftLanguageModes: [.v5]
)
