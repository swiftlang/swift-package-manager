// swift-tools-version: 999.0;(experimentalMultiLang)
import PackageDescription

let package = Package(
    name: "BridgingHeaderWithClangModule",
    targets: [
        .target(
            name: "Mixed",
            swiftSettings: [.bridgingHeader("Bridging.h", visibility: .internal)]
        ),
    ]
)
