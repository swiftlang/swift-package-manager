// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Async",
    targets: [
        .target(name: "Async"),
        .testTarget(name: "AsyncTests", dependencies: ["Async"]),
    ]
)
