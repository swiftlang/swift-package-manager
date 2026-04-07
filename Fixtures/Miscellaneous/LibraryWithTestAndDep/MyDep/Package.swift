// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyDep",
    products: [
        .library(name: "MyDep", targets: ["MyDep"]),
    ],
    targets: [
        .target(name: "MyDep"),
    ]
)
