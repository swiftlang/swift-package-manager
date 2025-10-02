// swift-tools-version: 5.6
import PackageDescription
let package = Package(
    name: "MyPackage",
    targets: [
        .target(
            name: "MyLibrary",
            plugins: [
                "MyPlugin",
            ]
        ),
        .plugin(
            name: "MyPlugin",
            capability: .buildTool()
        ),
    ]
)
