import PackageDescription

let package = Package(
    dependencies: [
        .Package(url: "../dep2", majorVersion: 1)
    ]
)
