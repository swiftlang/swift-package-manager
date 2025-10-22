// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "SwiftFramework",
    products: [
        .library(name: "SwiftFramework", type: .dynamic, targets: ["SwiftFramework"]),
    ],
    targets: [
        .target(
            name: "SwiftFramework",
            swiftSettings: [.unsafeFlags(["-enable-library-evolution"])]
        ),
    ]
)
