// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "CaseInsensitiveCollisions",
    products: [
        .executable(name: "foo", targets: ["footool"]),
    ],
    targets: [
        .executableTarget(name: "footool", dependencies: ["Foo"]),
        .target(name: "Foo"),
    ]
)
