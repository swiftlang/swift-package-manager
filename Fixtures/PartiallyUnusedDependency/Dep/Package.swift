// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Dep",
    products: [
        .library(
            name: "MyDynamicLibrary",
            type: .dynamic,
            targets: ["MyDynamicLibrary"]
        ),
        .executable(
            name: "MySupportExecutable",
            targets: ["MySupportExecutable"]
        )
    ],
    targets: [
        .target(
            name: "MyDynamicLibrary"
        ),
        .executableTarget(
            name: "MySupportExecutable",
            dependencies: ["MyDynamicLibrary"]
        )
    ]
)
