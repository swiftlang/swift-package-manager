// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Foo",
    dependencies: [
        .package(url: "https://localhost/foo/bar", branch: "#!~")
    ],
    targets: []
)
