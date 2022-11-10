// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "BrokenPkg",
    products: [
        .library(name: "BrokenPkg", targets: ["BrokenPkg", "Swift2"]),
    ],
    targets: [
        .target(name: "BrokenPkg", publicHeadersPath: "bestHeaders", cSettings: [ .define("FLAG"), ]),
        .target(name: "Swift2", dependencies: ["BrokenPkg"], cSettings: [ .define("FLAG"), ]),
    ]
)
