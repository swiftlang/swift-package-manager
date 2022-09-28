// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "AppPkg",
    dependencies: [
        .package(path: "../UtilsPkg"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Utils", package: "UtilsPkg")
            ],
            path: "./Sources/App"),
    ]
)
