// swift-tools-version: 5.6
import PackageDescription

let package = Package(
    name: "RemoteTool",
    products: [
        .executable(
            name: "RemoteTool",
            targets: ["RemoteTool"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "RemoteTool",
            dependencies: ["RemoteToolHelperLibrary"],
            path: "Tools/RemoteTool"
        ),
        .target(
            name: "RemoteToolHelperLibrary",
            path: "Libraries/RemoteToolHelperLibrary"
        )
    ]
)
