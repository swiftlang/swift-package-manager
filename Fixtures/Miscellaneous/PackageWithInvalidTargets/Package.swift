import PackageDescription

let package = Package(
    name: "MyApp",
    targets: [
        Target(name: "App", dependencies: [.Target(name: "Foo"), .Target(name: "Bar")]),
        Target(name: "Fake"),
        Target(name: "Bake")
    ]
)
