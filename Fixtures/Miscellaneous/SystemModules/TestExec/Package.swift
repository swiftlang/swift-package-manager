import PackageDescription

let package = Package(
    name: "TestExec",
    dependencies: [
        .Package(url: "../CFake", majorVersion: 1)
    ]
)
