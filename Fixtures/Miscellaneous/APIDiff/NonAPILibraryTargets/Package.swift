// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "NonAPILibraryTargets",
    products: [
        .library(name: "One", targets: ["Foo"]),
        .library(name: "Two", targets: ["Bar", "Baz"]),
        .executable(name: "Exec", targets: ["Exec", "Qux"])
    ],
    targets: [
        .target(name: "Foo"),
        .target(name: "Bar", dependencies: ["Baz"]),
        .target(name: "Baz"),
        .target(name: "Qux"),
        .target(name: "Exec", dependencies: ["Qux"])
    ]
)
