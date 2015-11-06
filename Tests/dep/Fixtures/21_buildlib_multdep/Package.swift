import PackageDescription

let package = Package(
    name: "21_buildlib_multdep",
    targets: [
        Target(
            name: "BarLib",
            dependencies: [.Target(name: "FooLib"), .Target(name:"FooBarLib")]),
        Target(
            name: "FooLib"),
        Target(
            name: "FooBarLib")])