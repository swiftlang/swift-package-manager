// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AppPkg",
    products: [
        .library(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(path: "./CoreDependency"),
    ],
    targets: [
        .target(
            name: "App",
            dependencies: ["AppCore"]
        ),
        .target(
            name: "AppCore",
            dependencies: [
                .product(
                    name: "CoreDependencyV3",
                    package: "CoreDependency",
                    moduleAliases: ["CoreDependencyV3": "CoreDependency"]
                ),
            ]
        ),
    ]
)
