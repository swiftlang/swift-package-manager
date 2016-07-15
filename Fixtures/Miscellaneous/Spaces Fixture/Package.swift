import PackageDescription

let package = Package(
    name: "Spaces Fixture",
    targets: [
        Target(name: "Module Name 2", dependencies: ["Module Name 1"])
    ])
