// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacRelay",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacRelay", targets: ["MacRelayApp"])],
    targets: [
        .target(name: "MacRelayCore"),
        .target(name: "MacRelayTransport", dependencies: ["MacRelayCore"]),
        .executableTarget(name: "MacRelayApp", dependencies: ["MacRelayCore", "MacRelayTransport"]),
        .testTarget(name: "MacRelayCoreTests", dependencies: ["MacRelayCore"]),
        .testTarget(name: "MacRelayTransportTests", dependencies: ["MacRelayCore", "MacRelayTransport"]),
    ],
    swiftLanguageModes: [.v5]
)
