// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UnhandledResource",
    targets: [
        .target(
            name: "MyLib",
            resources: [.process("missing.txt")]
        )
    ]
)
