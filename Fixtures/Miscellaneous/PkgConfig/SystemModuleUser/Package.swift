import PackageDescription

let package = Package(
    name: "SystemModuleUser",
    dependencies: [.Package(url: "../CSystemModule", majorVersion: 1)]
)
