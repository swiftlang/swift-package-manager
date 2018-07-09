// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "SystemModuleUser",
    dependencies: [
        .package(url: "../CSystemModule", from: "1.0.0"),
    ],
    targets: [
        .target(name: "SystemModuleUser", path: "Sources"),
    ]
)
