// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.
import PackageDescription

let package = Package(
    name: "MyRenderer",
    products: [
        .library(
            name: "MyRenderer",
            targets: ["MyRenderer"]),
    ],
    targets: [
        .target(
            name: "MyRenderer",
            dependencies: ["MySharedTypes"]),

        .target(name: "MySharedTypes")
    ]
)
