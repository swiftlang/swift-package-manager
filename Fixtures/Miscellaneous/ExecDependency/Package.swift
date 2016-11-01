import PackageDescription

let package = Package(
    name: "ExecDependency",
    targets: [
        Target(name: "exec2", dependencies: ["exec1"]),
        Target(name: "lib", dependencies: ["exec1", "exec2"]),
    ]
)
