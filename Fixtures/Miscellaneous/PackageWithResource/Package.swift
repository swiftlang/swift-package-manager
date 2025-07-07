// swift-tools-version:5.3
import PackageDescription

let package = Package(
    name: "AwesomeResources",
    targets: [
        .target(name: "AwesomeResources", resources: [.copy("hello.txt")]),
        .testTarget(name: "AwesomeResourcesTest", dependencies: ["AwesomeResources"], resources: [.copy("world.txt")])
    ]
)
