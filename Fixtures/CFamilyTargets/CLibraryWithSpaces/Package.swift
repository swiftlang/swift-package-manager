// swift-tools-version:4.2
import PackageDescription

let package = Package(
    name: "CLibraryWithSpaces",
    targets: [
        .target(name: "Bar", dependencies: ["Foo"]),
        .target(name: "Baz", dependencies: ["Foo", "Bar"]),
        .target(name: "Foo", dependencies: []),
        .target(name: "Bar with spaces", dependencies: []),
    ]
)
