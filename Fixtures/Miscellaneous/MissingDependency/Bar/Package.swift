import PackageDescription

let package = Package(
    name: "Bar",
    dependencies: [
        .Package(url: "../NonExistantPackage", majorVersion: 1)])
