// swift-tools-version: 6.5
import PackageDescription

let package = Package(
    name: "ObjCImplementationInSwift",
    targets: [
        .target(
            name: "MixedImpl",
            swiftSettings: [.enableExperimentalFeature("ObjCImplementation")]
        ),
        .executableTarget(name: "Runner", dependencies: ["MixedImpl"]),
    ]
)
