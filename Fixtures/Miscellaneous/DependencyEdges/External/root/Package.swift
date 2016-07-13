import PackageDescription

let package = Package(
    name: "root",
    dependencies: [
        .Package(url: "../dep2", majorVersion: 1)
    ]
)
