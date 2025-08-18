// swift-tools-version: 5.6
import PackageDescription
let package = Package(
    name: "MyPackage",
    products: [
        .library(
            name: "MyLibrary",
            targets: ["MyLibrary"]
        ),
        .executable(
            name: "MyExecutable",
            targets: ["MyExecutable"]
        ),
    ],
    targets: [
        .target(
            name: "MyLibrary"
        ),
        .executableTarget(
            name: "MyExecutable",
            dependencies: ["MyLibrary"]
        ),
        .plugin(
            name: "MyBuildToolPlugin",
            capability: .buildTool()
        ),
        .plugin(
            name: "MyCommandPlugin",
            capability: .command(
                intent: .custom(verb: "my-build-tester", description: "Help description")
            )
        ),
    ]
)
