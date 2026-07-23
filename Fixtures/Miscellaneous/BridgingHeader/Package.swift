// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "BridgingHeader",
    targets: [
        .executableTarget(
            name: "App",
            swiftSettings: [.bridgingHeader("Bridging.h", visibility: .public)]
        ),
    ]
)
