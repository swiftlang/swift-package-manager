// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "MyPlugin",
    products: [
        .plugin(
            name: "PackageScribblerPlugin",
            targets: ["PackageScribblerPlugin"]
        ),
    ],
    targets: [
        .plugin(
            name: "PackageScribblerPlugin",
            capability: .buildTool()
        )
    ]
)
