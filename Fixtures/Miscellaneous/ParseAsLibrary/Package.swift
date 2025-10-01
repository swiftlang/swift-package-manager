// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ParseAsLibrary",
    products: [],
    targets: [
        .executableTarget(name: "ExecutableTargetOneFileNamedMainMainAttr"),
        .executableTarget(name: "ExecutableTargetOneFileNamedMainNoMainAttr"),
        .executableTarget(name: "ExecutableTargetOneFileNotNamedMainMainAttr"),
        .executableTarget(name: "ExecutableTargetOneFileNotNamedMainNoMainAttr"),
        .executableTarget(name: "ExecutableTargetTwoFiles"),
    ]
)
