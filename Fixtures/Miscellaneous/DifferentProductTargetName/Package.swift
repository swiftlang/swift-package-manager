// swift-tools-version:5.2
import PackageDescription

let package = Package(
    name: "Foo",
    products: [
        .executable(name: "Foo", targets: ["Bar"]),
    ],
    targets: [
        .target(name: "Bar", path: "./"),
    ]
)
