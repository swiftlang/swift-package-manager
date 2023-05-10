// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "libPkg",
    products: [
        .executable(name: "ExampleApp", targets: ["ExampleApp"]),
        .library(name: "MainLib", targets: ["MainLib"]),
    ],
    targets: [
        .executableTarget(name: "ExampleApp", dependencies: ["MainLib"], packageAccess: false),
        .target(name: "MainLib", dependencies: ["Core"], packageAccess: true),
        .target(name: "Core", dependencies: ["DataManager"]),
        .target(name: "DataManager", dependencies: ["DataModel"]),
        .target(name: "DataModel"),
        .testTarget(name: "MainLibTests", dependencies: ["MainLib"]),
        .testTarget(name: "BlackBoxTests", dependencies: ["MainLib"], packageAccess: false)
    ]
)
