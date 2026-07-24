// swift-tools-version: 6.5
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
