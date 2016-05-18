import PackageDescription

let package = Package(
    name: "FooLib1",
    targets: [Target(name: "cli", dependencies: ["FooLib1"])])
