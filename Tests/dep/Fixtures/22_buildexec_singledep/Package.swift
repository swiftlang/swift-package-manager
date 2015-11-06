import PackageDescription

let package = Package(
    name: "22_buildexec_singledep",
    targets: [
        Target(
            name: "FooExec",
            dependencies: [.Target(name: "FooLib")]),
        Target(
            name: "FooLib")])