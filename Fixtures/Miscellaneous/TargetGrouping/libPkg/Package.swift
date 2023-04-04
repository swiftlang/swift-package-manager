// swift-tools-version:999.0
import PackageDescription

let package = Package(
    name: "libPkg",
    products: [
        .executable(name: "ExampleApp", targets: ["ExampleApp"]),
        .library(name: "MainLib", targets: ["MainLib"]),
    ],
    targets: [
        .executableTarget(name: "ExampleApp", group: .excluded, dependencies: ["MainLib"]),
        .target(name: "MainLib", group: .package, dependencies: ["Core"]),
        .target(name: "Core", dependencies: ["DataManager"]),
        .target(name: "DataManager", group: .package, dependencies: ["DataModel"]),
        .target(name: "DataModel"),
        .testTarget(name: "MainLibTests", group: .package, dependencies: ["MainLib"]),
        .testTarget(name: "BlackBoxTests", group: .excluded, dependencies: ["MainLib"])
    ]
)
