// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "App",
    dependencies: [.package(path: "../Library")],
    targets: [
        .executableTarget(name: "App", dependencies: [.product(name: "StaticLibrary", package: "Library")]),
    ]
)
