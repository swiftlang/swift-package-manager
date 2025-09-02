// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PackageConditionalDeps",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "PackageConditionalDeps",
            targets: ["PackageConditionalDeps"]
        ),
    ],
    traits: [
        .default(enabledTraits: ["EnablePackage1Dep"]),
        "EnablePackage1Dep",
        "EnablePackage2Dep"
    ],
    dependencies: [
        .package(path: "../Package1"),
        .package(path: "../Package2"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "PackageConditionalDeps",
            dependencies: [ 
                .product(
                    name: "Package1Library1",
                    package: "Package1",
                    condition: .when(traits: ["EnablePackage1Dep"])
                ),
                .product(
                    name: "Package2Library1",
                    package: "Package2",
                    condition: .when(traits: ["EnablePackage2Dep"])
                )
            ]
        ),
    ]
)
