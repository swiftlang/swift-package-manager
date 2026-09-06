// swift-tools-version: 6.5
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
