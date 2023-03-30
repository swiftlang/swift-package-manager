// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "libPkg",
    products: [
//        .executable(name: "ExampleApp", targets: ["ExampleApp"]),
        .library(name: "MainLib", targets: ["MainLib"]),
    ],
    targets: [
//        .executableTarget(name: "ExampleApp", group: .excluded, dependencies: ["MainLib"]),
        .target(name: "MainLib", group: .excluded, dependencies: ["Core"]),
        .target(name: "Core", group: .asdf, linkerSettings: [LinkerSetting.unsafeFlags(["-package-name", "mylib"])]),
        .testTarget(name: "MainLibTests", dependencies: ["MainLib"])
    ]
)