import PackageDescription

let package = Package(
    name: "foo",
    dependencies: [
        .Package(url: "../bar", majorVersion: 1)
    ]
)
