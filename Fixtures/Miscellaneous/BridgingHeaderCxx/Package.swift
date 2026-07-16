// swift-tools-version: 999.0
import PackageDescription

let package = Package(
    name: "BridgingHeaderCxx",
    targets: [
        .executableTarget(
            name: "App",
            swiftSettings: [
                .interoperabilityMode(.Cxx),
                .bridgingHeader("Bridging.h", visibility: .public),
            ]
        ),
    ]
)
