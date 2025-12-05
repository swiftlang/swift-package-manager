// swift-tools-version:6.0

import PackageDescription

let package = Package(name: "TestBinary",
    products: [
        .executable(name: "TestBinary", targets: ["TestBinary"]),
    ],
    targets: [
        .binaryTarget(name: "SwiftFramework", path: "SwiftFramework.xcframework"),
        .executableTarget(name: "TestBinary",
            dependencies: [
                .target(name: "SwiftFramework"),
            ]
        ),
    ]
)