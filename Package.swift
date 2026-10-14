// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacRelay",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacRelay", targets: ["MacRelayApp"])],
    targets: [
        .target(name: "MacRelayCore"),
        .target(name: "MacRelayTransport", dependencies: ["MacRelayCore"]),
        .target(name: "MacRelayInsertion", dependencies: ["MacRelayCore"]),
        .target(
            name: "MacRelayWispr", dependencies: ["MacRelayCore"], linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "MacRelayApp",
            dependencies: ["MacRelayCore", "MacRelayTransport", "MacRelayWispr", "MacRelayInsertion"]),
        .testTarget(name: "MacRelayCoreTests", dependencies: ["MacRelayCore"]),
        .testTarget(name: "MacRelayTransportTests", dependencies: ["MacRelayCore", "MacRelayTransport"]),
        .testTarget(name: "MacRelayInsertionTests", dependencies: ["MacRelayInsertion"]),
        .testTarget(
            name: "MacRelayWisprTests", dependencies: ["MacRelayCore", "MacRelayWispr"],
            linkerSettings: [.linkedLibrary("sqlite3")]),
    ],
    swiftLanguageModes: [.v5]
)
