// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "111920845-sample",
    platforms: [
        .macOS(.v10_15), // example uses swift concurrency which is only available in 10.15 or newer
    ],
    products: [
        .executable(name: "MyPluginExecutable", targets: ["MyPluginExecutable"]),
        .plugin(name: "MyPlugin", targets: ["MyPlugin"]),
    ],
    targets: [
        .executableTarget(name: "MyPluginExecutable"),
        .plugin(name: "MyPlugin", capability: .buildTool, dependencies: ["MyPluginExecutable"]),

        .target(name: "MyLibrary", plugins: ["MyPlugin"]),
        .executableTarget(name: "MyExecutable", dependencies: ["MyLibrary"]),
        .testTarget(name: "MyExecutableTests", dependencies: ["MyExecutable"]),
    ]
)
