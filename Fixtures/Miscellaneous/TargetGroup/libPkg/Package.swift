// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "libPkg",
    products: [
//        .executable(name: "ExampleApp", targets: ["ExampleApp"]),
        .library(name: "MainLib", targets: ["MainLib"]),
    ],
    targets: [
//        .executableTarget(name: "ExampleApp", group: .excluded, dependencies: ["MainLib"]),
        .target(name: "MainLib", group: .package),
        .testTarget(name: "MainLibTests", dependencies: ["MainLib"])
    ]
)
