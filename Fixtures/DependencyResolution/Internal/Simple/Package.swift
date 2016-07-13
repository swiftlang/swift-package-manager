import PackageDescription

let package = Package(
    name: "Simple",
    targets: [
        Target(name: "Foo", dependencies: [.Target(name: "Bar")])
    ])
 
