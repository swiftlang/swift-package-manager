// swift-tools-version:5.1

import PackageDescription

let package = Package(
    name: "package-info",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
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
