import PackageDescription

let package = Package(
    name: "App",
    dependencies: [
        .Package(url: "../CFoo", majorVersion: 1),
    ])
