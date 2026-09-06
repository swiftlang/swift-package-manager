// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "MixedCxxUsesSwiftHeader",
    targets: [
        .target(
            name: "MixedLib",
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .executableTarget(
            name: "Runner",
            dependencies: ["MixedLib"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
    ]
)
