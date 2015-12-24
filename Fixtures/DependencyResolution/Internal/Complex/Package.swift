import PackageDescription

let package = Package(
    targets: [
        Target(
            name: "Foo",
            dependencies: [.Target(name: "Bar")]),
        Target(
            name: "Bar",
            dependencies: [.Target(name: "Baz"), .Target(name:"Cat")]),
        Target(
            name: "Cat",
            dependencies: [.Target(name: "Sound")])
    ])
