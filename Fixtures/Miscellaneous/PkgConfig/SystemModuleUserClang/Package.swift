import PackageDescription

let package = Package(
    name: "SystemModuleUserClang",
    dependencies: [.Package(url: "../CSystemModule", majorVersion: 1)]
)
