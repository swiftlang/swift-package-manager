// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "BridgingHeaderSearchPaths",
    targets: [
        .executableTarget(
            name: "App",
            cSettings: [.headerSearchPath("extra_headers")],
            swiftSettings: [.bridgingHeader("Bridging.h", visibility: .public)]
        ),
    ]
)
