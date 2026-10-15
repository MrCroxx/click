// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "Click", platforms: [.macOS(.v14)],
    products: [.executable(name: "Click", targets: ["Click"]), .executable(name: "ClickDaemon", targets: ["ClickDaemon"])],
    targets: [
        .target(name: "ClickCore", resources: [.process("Resources")]),
        .target(name: "ClickIPC"),
        .target(name: "VirtualHID", exclude: ["LICENSE.md", "Licenses", "UPSTREAM.md", "vendor"], cxxSettings: [.headerSearchPath("vendor"), .unsafeFlags(["-std=c++23"])], linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("CoreFoundation")]),
        .executableTarget(name: "ClickDaemon", dependencies: ["ClickCore", "ClickIPC", "VirtualHID"]),
        .executableTarget(name: "Click", dependencies: ["ClickCore", "ClickIPC"]),
        .testTarget(name: "ClickCoreTests", dependencies: ["ClickCore"]),
        .testTarget(name: "ClickRuntimeTests", dependencies: ["Click", "ClickCore"])
    ], swiftLanguageModes: [.v5]
)
