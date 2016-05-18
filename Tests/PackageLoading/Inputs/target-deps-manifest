import PackageDescription

let package = Package(
    name: "TargetDeps",
    targets: [
        Target(
            name: "sys",
            dependencies: [.Target(name: "libc")]),
        Target(
            name: "dep",
            dependencies: [.Target(name: "sys"), .Target(name: "libc")])])
