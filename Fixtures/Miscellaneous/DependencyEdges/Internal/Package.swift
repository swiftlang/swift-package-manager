import PackageDescription

let package = Package(name: "Internal", targets: [Target(name: "Foo", dependencies: ["Bar"])])
