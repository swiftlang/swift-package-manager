import PackageDescription

let package = Package(
    name: "Foo",
    targets: [
        Target(name: "FooLib"),
        Target(name: "Foo2Lib"
            ,dependencies: ["FooLib"]
        ),
        Target(name: "Foo_macOS", dependencies: ["FooLib"]),
        Target(name: "Foo_iOS", dependencies: ["Foo2Lib"]),
    ]
)
