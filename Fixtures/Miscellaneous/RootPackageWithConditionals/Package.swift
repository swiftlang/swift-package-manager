// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "client",
    products: [
        .library(name: "client", targets: ["client"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "client", dependencies: [
        	.target(name: "linuxOnly", condition: .when(platforms: [.linux]))
        ]),
        .target(name: "linuxOnly"),
    ]
)
