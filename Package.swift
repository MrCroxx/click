// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Click", platforms: [.macOS(.v14)],
    products: [.executable(name: "Click", targets: ["Click"])],
    targets: [
        .target(name: "ClickCore"),
        .executableTarget(name: "Click", dependencies: ["ClickCore"]),
        .testTarget(name: "ClickCoreTests", dependencies: ["ClickCore"]),
        .testTarget(name: "ClickRuntimeTests", dependencies: ["Click", "ClickCore"])
    ], swiftLanguageModes: [.v5]
)
