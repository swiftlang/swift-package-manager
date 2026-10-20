// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "package-with-build-tool-plugin",
    products: [
        .library(name: "Lib", targets: ["Lib"]),
    ],
    targets: [
        .executableTarget(name: "Gen"),
        .plugin(
            name: "GenPlugin",
            capability: .buildTool(),
            dependencies: ["Gen"],
        ),
        .target(
            name: "Lib",
            plugins: ["GenPlugin"],
        ),
    ]
)
