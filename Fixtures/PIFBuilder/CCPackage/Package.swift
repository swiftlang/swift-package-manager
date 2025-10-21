// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "CCPackage",
    products: [
        .library(name: "CCTarget", type: .static, targets: ["CCTarget"]),
    ],
    targets: [
        .target(name: "CCTarget", ),
        .executableTarget(name: "executable", dependencies: ["CCTarget"]),
    ]
)
