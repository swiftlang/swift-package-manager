// swift-tools-version: 999.0;(experimentalMultiLang)
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
