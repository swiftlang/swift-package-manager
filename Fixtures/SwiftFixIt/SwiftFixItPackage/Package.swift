// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "SwiftFixItPackage",
    targets: [
        .target(name: "Diagnostics", path: "Sources", exclude: ["Fixed"]),
    ]
)
