import PackageDescription

let package = Package(
    name: "dep2",
    dependencies: [
        .Package(url: "../dep1", versions: "1.1.0"..<"2.0.0"),
    ]
)
