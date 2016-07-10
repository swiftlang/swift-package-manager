import PackageDescription

let package = Package(
    name: "SwiftCMixed",
    targets: [
        Target(name: "SeaExec", dependencies: ["SeaLib"]),
        Target(name: "CExec", dependencies: ["SeaLib"])
    ]
)
