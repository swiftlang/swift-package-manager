import PackageDescription

let package = Package(
    name: "blocks",
    targets: [
        Target(name: "swiftexec", dependencies: ["clib"])
    ]
)
