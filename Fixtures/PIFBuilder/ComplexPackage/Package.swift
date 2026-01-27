// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "ComplexPackage",
products: [
    .executable(name: "exec-1", targets: ["exec"]),
    .executable(name: "exec-2", targets: ["exec"])
],
targets: [
    .target(
        name: "corecpp",
        dependencies: []
    ),
    .target(
        name: "exec",
        dependencies: ["corecpp"]
    ),
        .testTarget(
            name: "ComplexPackageTests",
            dependencies: ["exec"]
        ),
        .testTarget(
            name: "ComplexPackageTests2",
            dependencies: ["exec"]
        )
    ]
)
