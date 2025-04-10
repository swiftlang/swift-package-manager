// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "DemoKit",
    products: [
        .library(name: "DemoKit", targets: ["DemoKit"]),
    ],
    targets: [
        .plugin(
            name: "GenerateSymbolGraphPlugin",
            capability: .command(
                intent: .custom(
                    verb: "generate-symbol-graph",
                    description: "Generate symbol graph for all Swift source targets."
                )
            )
        ),
        .binaryTarget(name: "FooKit", path: "FooKit.xcframework"),
        .target(
            name: "DemoKit",
            dependencies: ["FooKit"]
        ),   
    ]
)
