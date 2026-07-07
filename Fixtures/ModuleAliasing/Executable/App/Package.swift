// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .package(path: "../Utils"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(
                    name: "Utils",
                    package: "Utils",
                    moduleAliases: ["Utils": "AppUtils"]
                ),
            ]
        ),
    ]
)
