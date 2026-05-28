// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyDynDep",
    products: [
        .library(name: "MyDynDep", type: .dynamic, targets: ["MyDynDep"]),
    ],
    targets: [
        .target(name: "MyDynDep"),
    ]
)
