// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .executable(name: "Exe1", targets: ["Foo"]),
        .executable(name: "Exe2", targets: ["Foo"]),
    ],
    targets: [
        .executableTarget(name: "Foo", path: "./"),
    ]
)
