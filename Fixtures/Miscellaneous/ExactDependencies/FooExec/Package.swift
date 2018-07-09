// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "FooExec",
    products: [
        .executable(name: "FooExec", targets: ["FooExec"]),
    ],
    dependencies: [
        .package(url: "../FooLib1", from: "1.0.0"),
        .package(url: "../FooLib2", from: "1.0.0"),
    ],
    targets: [
        .target(name: "FooExec", dependencies: ["FooLib1", "FooLib2"], path: "./"),
    ]
)
