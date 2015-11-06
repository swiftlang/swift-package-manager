import PackageDescription

let package = Package(
    name: "20_buildlib_singledep",
    targets: [
        Target(
            name: "BarLib",
            dependencies: [.Target(name: "FooLib")]),
        Target(
            name: "FooLib")])