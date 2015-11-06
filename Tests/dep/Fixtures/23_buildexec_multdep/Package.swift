import PackageDescription

let package = Package(
    name: "21_buildlib_multdep",
    targets: [
        Target(
            name: "FooExec",
            dependencies: [.Target(name: "FooLib1"), .Target(name:"FooLib2")]),
        Target(
            name: "FooLib1"),
        Target(
            name: "FooLib2")])