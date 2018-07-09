// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "Foo",
    targets: [
        .target(name: "Bar", dependencies: ["Baz", "Cat"]),
        .target(name: "Baz", dependencies: []),
        .target(name: "Cat", dependencies: ["Sound"]),
        .target(name: "Foo", dependencies: ["Bar"]),
        .target(name: "Sound", dependencies: []),
    ]
)
