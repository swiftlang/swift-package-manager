// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "Simple",
    targets: [
        .target(name: "Simple", plugins: ["SimplePlugin"]),
        .testTarget(name: "SimpleTests", dependencies: ["Simple"]),
        .plugin(name: "SimplePlugin", capability: .buildTool()),
    ]
)
