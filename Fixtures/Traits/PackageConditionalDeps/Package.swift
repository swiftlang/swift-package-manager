// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "PackageConditionalDeps",
    products: [
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
