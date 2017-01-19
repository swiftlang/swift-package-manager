import PackageDescription

let package = Package(
    name: "SwiftCMixed",
    targets: [
        Target(name: "SeaExec", dependencies: ["SwiftLib"]),
        Target(name: "SwiftLib", dependencies: ["SeaLib"]),
    ]
)
