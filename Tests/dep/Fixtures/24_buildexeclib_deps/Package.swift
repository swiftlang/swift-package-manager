import PackageDescription

let package = Package(
    name: "21_buildlib_multdep",
    targets: [
        Target(
            name: "Foo",
            dependencies: [.Target(name: "DepOnFooLib")]),
        Target(
            name: "Bar",
            dependencies: [.Target(name: "DepOnFooLib"), .Target(name:"BarLib")]),
        Target(
            name: "DepOnFooLib",
            dependencies: [.Target(name: "FooLib")]),
        Target(
            name: "DepOnFooExec",
            dependencies: [.Target(name: "FooLib")]),
        Target(
            name: "FooLib"),
        Target(
            name: "BarLib")])