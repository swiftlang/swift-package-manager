// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "package-info",
    dependencies: [
        // This just points to the SwiftPM at the root of this repository.
        .package(path: "../../"),
        // You will want to depend on a stable semantic version instead:
        // .package(url: "https://github.com/apple/swift-package-manager", .exact("0.4.0"))
    ],
    targets: [
        .target(
            name: "package-info",
            dependencies: ["SwiftPM"]),
    ]
)
