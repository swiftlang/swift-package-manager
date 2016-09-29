import PackageDescription

let package = Package(
    name: "foo",
    dependencies: [
        .Package(url: "../bar", majorVersion: 1),
        .Package(url: "../baz", majorVersion: 1),
    ]
)
